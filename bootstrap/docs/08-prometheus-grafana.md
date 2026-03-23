# Step 08: Prometheus + Grafana Monitoring

## Overview

Deploy a **lightweight Prometheus + Grafana** monitoring stack on the K3s cluster.

This uses a **minimal StatefulSet approach** (no Prometheus Operator overhead) suitable for resource-constrained environments.

| Component | Deployment | Storage | Memory |
|-----------|-----------|---------|--------|
| Prometheus | StatefulSet on pi4controller | Longhorn PVC (3 GB, 7-day retention) | 50m / 64Mi |
| Grafana | Deployment on pi4controller | Longhorn PVC (1 GB) | 25m / 32Mi |

## Architecture

- **Prometheus StatefulSet** — minimal, no operator, ConfigMap-based config
- **Scrapes essential metrics:** nodes, pods, Kubernetes API
- **Grafana Deployment** — pre-configured Prometheus datasource
- **Both exposed via Traefik Ingress** on `prometheus.cluster.local` and `grafana.cluster.local`
- **No node exporters or kube-state-metrics** — uses Kubernetes API directly for metrics

## Prerequisites

- K3s cluster running (steps 01–03)
- MetalLB configured (step 04)
- Traefik ingress controller deployed (step 05)
- **Longhorn storage** with working PVCs (step 06)

## Installation

### Step 1: Prerequisites

- K3s cluster running (steps 01–03)
- MetalLB configured (step 04)
- Traefik ingress controller deployed (step 05)
- **Longhorn storage** with working PVCs (step 06)

All should be deployed via `helmfile sync` in the core bootstrap.

### Step 2: Deploy monitoring

Once the core stack is stable, deploy Prometheus and Grafana:

```bash
kubectl apply -f cluster/monitoring/
```

This creates:
- ConfigMap with Prometheus scrape config
- Prometheus StatefulSet with Longhorn PVC
- Grafana Deployment with Longhorn PVC
- RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
- Traefik Ingress

### Step 3: Verify deployment

```bash
kubectl -n monitoring get pods -w
```

Wait for all pods to be `Running`:
- `prometheus-0` (1-2 min to pull image + initialize)
- `grafana-xxxxx` (should be instant)

Check storage:

```bash
kubectl -n monitoring get pvc
```

Both PVCs should be `Bound`.

### Step 4: Access dashboards

From your laptop, add to `/etc/hosts`:

```
192.168.1.10 prometheus.cluster.local grafana.cluster.local
```

Then visit:
- **Prometheus**: http://prometheus.cluster.local
  - Go to `/graph` to query metrics
  - Check `/targets` to verify scraping is working
  
- **Grafana**: http://grafana.cluster.local
  - Login: `admin` / `admin` (change password in production!)
  - Prometheus datasource is pre-configured
  - Go to **Dashboards** → **Browse** to import or create dashboards

### Step 5: Verify metrics collection

In **Prometheus** (`/targets`), you should see:
- `kubernetes-nodes` — node metrics via API proxy
- `kubernetes-pods` — pod metrics (if pods have `prometheus.io/scrape: "true"` annotations)
- `prometheus` — Prometheus itself

## Troubleshooting

### Prometheus pod stuck in `Init:0/1` or `Pending`

This usually means the PVC isn't binding. Check:

```bash
kubectl -n monitoring describe pvc prometheus-storage-prometheus-0
kubectl -n monitoring describe pod prometheus-0
```

If PVC is stuck `Pending`, Longhorn may not have capacity. Check:

```bash
kubectl -n longhorn-system get pvc
kubectl top nodes  # Ensure controller has free disk
```

### Grafana datasource shows "Health: Server Error"

Verify Prometheus is running and reachable:

```bash
kubectl -n monitoring get pod -l app=prometheus
kubectl -n monitoring logs prometheus-0
```

Try port-forward to test connectivity:

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then: curl http://localhost:9090/-/healthy
```

### Can't reach http://prometheus.cluster.local

Verify Ingress is set up:

```bash
kubectl -n monitoring get ingress
```

Ensure your `/etc/hosts` is updated correctly, or add DNS records for those hostnames.

### Memory usage too high

The lightweight setup uses **~100-150MB total**. If higher, check:

```bash
kubectl top pods -n monitoring
```

If Prometheus is using >200MB, it may be scraping too many metrics. Reduce retention or scrape interval in the ConfigMap:

```bash
kubectl -n monitoring edit configmap prometheus-config
```

Reduce `retention.time` from `7d` to `3d` or lower `scrape_interval` from `30s` to `60s`.

## Resource Budget

| Component | CPU Request | Memory Request |
|-----------|------------|----------------|
| Prometheus | 50m | 64Mi |
| Grafana | 25m | 32Mi |
| **Total** | **75m** | **96Mi** |

Total impact on cluster: **~0.3% CPU, 0.1% memory** (minimal overhead).
