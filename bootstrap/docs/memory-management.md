# Memory Management & OOM Prevention

The Pi 4 controller runs everything — K3s control plane, ArgoCD, Longhorn, Traefik,
MetalLB, and the full monitoring/logging stack. At ~3.5GB combined peak, there's
little headroom on 4GB. This document explains how the cluster is protected from
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

All monitoring and ArgoCD components have been updated so requests reflect real steady-state usage:

| Component | Old request | New request | Limit |
|-----------|-------------|-------------|-------|
| Prometheus | 256Mi | 384Mi | 512Mi |
| Loki | 64Mi | 128Mi | 256Mi |
| Promtail (per node) | 32Mi | 32Mi | 64Mi |
| ArgoCD controller | — (none) | 256Mi | 512Mi |
| ArgoCD server | — (none) | 128Mi | 256Mi |
| ArgoCD repo-server | — (none) | 128Mi | 256Mi |
| ArgoCD redis | — (none) | 32Mi | 128Mi |

ArgoCD `notifications` and `applicationSet` controllers are **disabled** — unused in
this cluster. This saves ~46Mi of untracked memory.

Grafana is **disabled** until the cluster has sufficient headroom. Re-enable by adding
`grafana.yaml` back to `cluster/argocd/addons/kustomization.yaml` and then manually
creating the ArgoCD Application.

---

## Memory Budget (Pi 4 Controller)

Approximate steady-state peak usage across all system components:

| Category | Estimate |
|----------|----------|
| OS / kernel / systemd | ~200MB (reserved: 512MB) |
| K3s control plane pods | ~500MB |
| Longhorn | ~350MB |
| Traefik + MetalLB | ~100MB |
| ArgoCD | ~350MB |
| Prometheus | ~350MB |
| Loki | ~100MB |
| Promtail (controller) | ~32MB |
| **Total (approx)** | **~2.0GB** |
| **Headroom to soft eviction** | **~0.5GB** |

This leaves ~1.3GB before kubelet soft eviction starts. That's the budget for
application workloads deployed on the controller, and for burst spikes.

---

## Safe Deployment Procedure

Deploying multiple new workloads simultaneously is how the cluster crashed.
ArgoCD syncs everything at once — a memory spike across 3–4 pods starting
simultaneously can exceed available memory before steady state settles.

**Always follow this sequence:**

```bash
# 1. Check current memory before any deploy
kubectl top nodes

# 2. Deploy one component at a time; wait for it to be Running and stable
kubectl rollout status -n monitoring statefulset/prometheus
kubectl top pod -n monitoring

# 3. Only proceed to the next component once memory has settled
kubectl top nodes  # should return to baseline ± ~50MB

# 4. If deploying via ArgoCD, use manual sync (not auto-sync) during heavy rollouts:
#    ArgoCD UI → App → Sync → select specific resources → sync one at a time
```

**Rule of thumb:** if `kubectl top nodes` shows the controller above 80% memory,
stop and investigate before deploying anything new.

---

## Prometheus Alerts

Two alert rules watch for memory pressure (`cluster/monitoring/prometheus/prometheus-config.yaml`):

| Alert | Threshold | Severity |
|-------|-----------|----------|
| `NodeMemoryPressureWarning` | >75% node memory used for 2m | warning |
| `NodeMemoryPressureCritical` | <400Mi available for 1m | critical |
| `ContainerNearMemoryLimit` | Container at >90% of its limit for 5m | warning |

These appear in Grafana under Alerting, or can be queried in Prometheus at
`http://prometheus.cluster.local`.

---

## After a Reflash

When the SD card is reflashed, the swap file and sysctl settings are lost.
They are restored by running:

```bash
# On the fresh Pi 4 (after first boot):
bash bootstrap/scripts/setup-controller.sh      # creates swap + sysctl

# Then reinstall K3s (eviction flags are baked in):
sudo bash bootstrap/scripts/install-k3s-server.sh
```

See `bootstrap/docs/02-k3s-server.md` for the full reinstall procedure.

---

## Considerations for Future Growth

- **K3s official SD card warning**: The K3s docs explicitly state *"SD cards and eMMC cannot handle the IO load"* for etcd write operations. We use K3s in single-server mode (SQLite, not etcd), which is far less write-intensive — but this is still a long-term reliability concern. An external USB SSD for the Pi 4's storage would significantly improve stability.
- **Pi Zero 2 W is at the K3s minimum**: K3s requires 512MB RAM for agents; Pi Zeros have exactly 512MB. They are not candidates for any additional system workloads.
- **Monitoring on a worker**: Prometheus could move to a worker node if the stack grows, but Pi Zero 2 W has only 512MB — not viable without a beefier worker node.
- **Disable node-exporter on Pi Zeros**: Pi Zeros are already memory-constrained.
  If promtail causes OOMKills on workers, remove the Pi Zero toleration from the
  Promtail DaemonSet.
