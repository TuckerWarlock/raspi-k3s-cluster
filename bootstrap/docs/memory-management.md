# Memory Management & OOM Prevention

The Pi 4 controller runs the K3s control plane plus every pod that needs the LAN or the USB
drive: Traefik, MetalLB, the ArgoCD application-controller, VictoriaMetrics, and Gatus. The
rest of ArgoCD runs on the Pi Zeros. There's little headroom on 4GB. This document explains how the cluster is protected from
memory-induced crashes and how to deploy new workloads safely.

---

## Why SD Card Corruption Happens

When the Linux OOM killer fires, it terminates processes randomly. If the killed
process had in-flight writes to the SD card (journald, etcd, the container runtime),
the filesystem can be left in an inconsistent state. A power cycle after this often
finds a corrupt rootfs — hence the reflash.

The goal is to **never let the kernel reach OOM**. Instead, Kubernetes should evict
pods gracefully before memory runs out.

---

## Defence-in-Depth Strategy

Three layers protect the cluster, each stopping memory exhaustion earlier than the last:

```
Layer 1 — Swap (last resort, ~1GB)
    ↑ kernel reaches here only if layers 2+3 failed
Layer 2 — Kubelet eviction (soft at 512Mi avail, hard at 300Mi avail)
    ↑ pods get evicted gracefully before kernel OOM fires
Layer 3 — Accurate resource requests (scheduler sees real usage)
    ↑ scheduler won't overcommit in the first place
```

### Layer 1 — Swap file

A 1GB swapfile at `/swapfile` is created by `setup-controller.sh`. It is **not** a
performance solution — swap on an SD card is slow. It is purely a crash buffer: if
layers 2 and 3 fail, the kernel swaps to disk instead of killing processes and
corrupting the filesystem.

`vm.swappiness=10` means the kernel almost never uses swap proactively; it only
engages under genuine memory pressure.

### Layer 2 — Kubelet eviction thresholds

Configured in `install-k3s-server.sh` via `--kubelet-arg`:

| Flag | Value | Meaning |
|------|-------|---------|
| `system-reserved` | `cpu=250m,memory=512Mi` | Reserve 512MB for the OS/kernel/systemd — not allocatable to pods |
| `eviction-soft` | `memory.available<512Mi` | Kubelet marks node as MemoryPressure; starts evicting pods after the grace period |
| `eviction-soft-grace-period` | `memory.available=2m` | Threshold must hold for 2 minutes before soft eviction begins |
| `eviction-max-pod-grace-period` | `90` | Pods get up to 90 seconds to terminate cleanly during soft eviction |
| `eviction-hard` | `memory.available<300Mi` + disk defaults | Kubelet force-evicts pods immediately (0s grace) |

**Important:** The Kubernetes docs state that setting any custom `eviction-hard` value **disables all other defaults** — they become zero, not inherited. The K8s defaults are:
- `memory.available<100Mi`
- `nodefs.available<10%`
- `imagefs.available<15%`
- `nodefs.inodesFree<5%` (Linux)

Our flag explicitly restores all the disk defaults alongside the tightened memory threshold:
```
eviction-hard=memory.available<300Mi,nodefs.available<10%,imagefs.available<15%,nodefs.inodesFree<5%
```

If you ever adjust this flag, you must re-include all thresholds you want active.

> **Re-applying after a reflash:** These flags are baked into the `install-k3s-server.sh`
> invocation. Re-running the script after a reflash automatically re-applies them.

### Layer 3 — Accurate resource requests

Kubernetes scheduling decisions are based on **requests**, not limits. A pod with
`request=64Mi, limit=256Mi` looks cheap to the scheduler but can consume 4× more memory
than advertised. This causes over-scheduling — the scheduler places pods that collectively
exceed available memory.

Requests should reflect real steady-state usage. Current settings and measured usage
(`kubectl top pods -A`, idle, November 2026):

| Component | Node | Request | Limit | Measured |
|-----------|------|---------|-------|----------|
| ArgoCD application-controller | pi4controller | 256Mi | 512Mi | ~160–250Mi (400Mi+ while retrying failed syncs) |
| VictoriaMetrics | pi4controller | 128Mi | 256Mi | ~120Mi |
| MetalLB speaker / controller | pi4controller | 64Mi / 32Mi | 128Mi / 128Mi | ~20Mi / ~30Mi (FRR sidecars disabled; were +34Mi) |
| Traefik | pi4controller | 64Mi | 128Mi | ~25Mi |
| Gatus | pi4controller | 32Mi | 64Mi | ~10Mi |
| ntfy | pi4controller | 32Mi | 64Mi | ~15Mi |
| vmalert / Alertmanager | pi4controller | 32Mi / 32Mi | 64Mi / 64Mi | ~5Mi / ~12Mi |
| kube-state-metrics | Pi Zero | 32Mi | 64Mi | not yet measured |
| ArgoCD server | Pi Zero | 128Mi | 256Mi | ~65–100Mi |
| ArgoCD repo-server | Pi Zero | 128Mi | 384Mi | ~65–115Mi |
| ArgoCD redis | Pi Zero | 32Mi | 128Mi | ~20Mi |

ArgoCD `notifications` and `applicationSet` controllers are **disabled** — unused in
this cluster.

---

## Memory Budget (Pi 4 Controller)

Measured after the November 2026 rebuild, everything idle:

| Category | Usage |
|----------|-------|
| Pods on the controller (table above, plus CoreDNS, metrics-server, local-path) | ~460Mi |
| K3s server process, containerd, OS | ~1.4Gi |
| `tailscaled` (host service, not in cAdvisor's view — check `systemctl status tailscaled`) | not yet measured |
| **Node total (`kubectl top nodes`)** | **~1.85–1.95Gi (62–66% of allocatable)** |
| **Headroom before soft eviction (512Mi available)** | **~1.3Gi** |

That headroom is the budget for new controller workloads and for burst spikes (image pulls,
chart renders, pod restarts). The Pi Zeros idle at 210–250Mi each (45–55%).

---

## Safe Deployment Procedure

Deploying multiple new workloads simultaneously is how the cluster crashed.
ArgoCD syncs everything at once — a memory spike across 3–4 pods starting
simultaneously can exceed available memory before steady state settles.

**Push one new app per commit**, and wait for each to settle before pushing the next:

```bash
# 1. Baseline before the push
kubectl top nodes

# 2. Push one app; pull it in now instead of waiting for the 5-minute poll
kubectl -n argocd annotate app cluster-addons workloads argocd.argoproj.io/refresh=normal --overwrite
kubectl -n argocd get applications -w          # wait for Synced + Healthy

# 3. Check the new pod and the node
kubectl top pod -n <namespace>
kubectl top nodes   # back to baseline + the new pod's usage

# 4. Only then push the next app
```

**Rule of thumb:** if `kubectl top nodes` shows the controller above 80% memory,
stop and investigate before deploying anything new.

---

## Alerting

**Service health:** Gatus sends a push to the `cluster-status` ntfy topic when any check fails
3 times in a row (~3 minutes), and again when it recovers (`workloads/gatus/configmap.yaml`).

**Memory and scraping:** vmalert evaluates these rules every minute against VictoriaMetrics;
Alertmanager pushes firing and resolved alerts to the same ntfy topic
(`cluster/monitoring/vmalert/values.yaml`):

| Alert | Fires when | Severity |
|---|---|---|
| `ControllerMemoryLow` | pi4controller has under 800Mi available for 2m (soft eviction is at 512Mi) | critical |
| `WorkerMemoryLow` | a Pi Zero has under 120Mi available for 5m (hard eviction is at 100Mi) | warning |
| `ContainerNearMemoryLimit` | a container is above 90% of its memory limit for 10m | warning |
| `ContainerOOMKilled` | a container was OOM-killed in the last 15m | warning |
| `ScrapeTargetDown` | a VictoriaMetrics scrape target is down for 10m | warning |
| `PodCrashLooping` | a container is in `CrashLoopBackOff` for 5m | critical |
| `PodRestartingOften` | a container restarted 3+ times in the last hour (catches restarts that never reach `CrashLoopBackOff`) | warning |
| `PodNotReady` | a Running/Pending pod is not Ready for 10m | warning |
| `DeploymentReplicasMismatch` / `StatefulSetReplicasMismatch` | desired ≠ available/ready replicas for 10m | warning |
| `DaemonSetNotReady` | a DaemonSet has pods not ready for 10m | warning |
| `NodeNotReady` | a node's `Ready` condition is false/unknown for 5m | critical |
| `NodePressure` | a node reports `MemoryPressure`, `DiskPressure`, or `PIDPressure` for 2m (the kubelet is evicting) | critical |
| `PVCPending` | a PVC is `Pending` for 15m | warning |

The last nine come from kube-state-metrics, which watches only pods, deployments,
statefulsets, daemonsets, nodes, and PVCs and exposes only the 13 metrics these rules use
(`cluster/monitoring/kube-state-metrics/values.yaml`).

"Available" is `machine_memory_bytes` minus the root cgroup's working set — the same number
the kubelet uses for eviction. Alertmanager sends one notification per alert and object (node,
pod, deployment, …), and re-sends a still-firing alert every 12h.

Ad hoc, check by hand: `kubectl top nodes`, or query VictoriaMetrics at
`https://vm.cluster.local/vmui`.

---

## After a Reflash

[rebuild.md](rebuild.md) covers everything. The memory-related steps that are easy to miss:

- `setup-controller.sh` (step 1.3) — swap and sysctls are lost on every reflash
- `install-k3s-server.sh` (step 1.6) — the eviction flags live in this script
- The USB drive mount (step 1.5) — without it, images and PVCs fill the SD card

---

## Considerations for Future Growth

- **SD card reliability**: The K3s docs state *"SD cards and eMMC cannot handle the IO load"* for etcd. This cluster uses single-server SQLite, which writes far less — but a USB SSD boot for the Pi 4 would still be the biggest stability win.
- **Pi Zero 2 W is at the K3s minimum**: K3s requires 512MB RAM for agents; Pi Zeros have exactly 512MB. Keep anything scheduled on them small.
- **VictoriaMetrics series count**: K3s exposes the whole control plane through the API server endpoint, and its latency histogram buckets were ~121k of ~170k series — enough to push VictoriaMetrics to 190Mi of its 256Mi and to OOM-kill it on one heavy query (Nov 2026). They're now dropped at ingest (`server.relabel` in `cluster/monitoring/victoria-metrics/values.yaml`), leaving ~47k. When adding a scrape target, check its series count first (`count({job="<job>"})`) and drop what isn't needed before raising the limit.
- **Heavy queries can OOM VictoriaMetrics**: `search.maxUniqueTimeseries=60000` makes a query that touches too many series fail with an error instead. Avoid `count()` or regex matches over every metric name.
- **node-exporter**: deliberately not deployed — cAdvisor via the kubelet covers container memory and CPU without a DaemonSet on the Pi Zeros.
