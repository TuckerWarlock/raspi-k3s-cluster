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
| `system-reserved` | `cpu=250m,memory=512Mi` | Reserve 512MB for the OS/kernel/systemd — pods cannot consume this |
| `eviction-soft` | `memory.available<512Mi` | Kubelet starts gracefully evicting pods (with 2m grace period) |
| `eviction-hard` | `memory.available<300Mi` | Kubelet force-evicts pods immediately |

With 512MB system-reserved, the Pi 4 effectively has ~3.5GB available for pods.
Eviction starts before memory is fully exhausted, giving pods time to shut down cleanly.

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
| Grafana | 32Mi | 64Mi | 128Mi |
| Promtail (per node) | 32Mi | 32Mi | 64Mi |
| ArgoCD controller | — (none) | 256Mi | 512Mi |
| ArgoCD server | — (none) | 128Mi | 256Mi |
| ArgoCD repo-server | — (none) | 128Mi | 256Mi |
| ArgoCD redis | — (none) | 32Mi | 128Mi |

---

## Memory Budget (Pi 4 Controller)

Approximate steady-state peak usage across all system components:

| Category | Estimate |
|----------|----------|
| OS / kernel / systemd | ~200MB (reserved: 512MB) |
| K3s control plane pods | ~500MB |
| Longhorn | ~400MB |
| Traefik + MetalLB | ~100MB |
| ArgoCD | ~400MB |
| Prometheus | ~384MB |
| Loki | ~128MB |
| Grafana | ~64MB |
| Promtail (controller) | ~32MB |
| **Total (approx)** | **~2.2GB** |
| **Headroom to soft eviction** | **~1.3GB** |

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

- **Monitoring on a worker**: Prometheus and Grafana could move to a worker node if
  the monitoring stack keeps growing, but Pi Zero 2 W has only 512MB — not viable
  without a beefier worker node.
- **Reduce Loki retention**: Dropping `retention_period` from 7d to 3d cuts Loki's
  disk and memory usage. Edit `cluster/monitoring/loki/loki-configmap.yaml`.
- **Increase scrape interval**: `scrape_interval: 60s` (from 30s) halves Prometheus
  ingestion load with minimal practical impact for a homelab.
- **Disable node-exporter on Pi Zeros**: Pi Zeros are already memory-constrained.
  If promtail causes OOMKills on workers, remove the Pi Zero toleration from the
  Promtail DaemonSet.
