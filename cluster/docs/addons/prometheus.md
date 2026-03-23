# Prometheus Monitoring

Deploy a **lightweight Prometheus** metrics collection on the K3s cluster.

This uses a **minimal StatefulSet approach** (no Prometheus Operator overhead) suitable for resource-constrained environments.

| Component | Deployment | Storage | Memory |
|-----------|-----------|---------|--------|
| Prometheus | StatefulSet on pi4controller | Longhorn PVC (3 GB, 7-day retention) | 50m / 64Mi |

## Architecture

- **Prometheus StatefulSet** — minimal, no operator, ConfigMap-based config
- **Scrapes essential metrics:** nodes, pods, Kubernetes API
- **Exposed via Traefik Ingress** on `prometheus.cluster.local`
- **7-day retention** with tunable configuration
- **30-second scrape interval** — essential metrics only

## Prerequisites

- K3s cluster running
- MetalLB configured
- Traefik ingress controller deployed
- **Longhorn storage** with working PVCs

## Installation

### Deploy Prometheus

Via ArgoCD (recommended):
```bash
kubectl apply -f cluster/argocd/root-application.yaml
# ArgoCD will deploy Prometheus automatically
```

Manual deployment:
```bash
kubectl apply -k cluster/monitoring/prometheus/
```

### Verify deployment

```bash
kubectl -n monitoring get pods -w
```

Wait for `prometheus-0` to be `Running` (1-2 min).

Check storage:
```bash
kubectl -n monitoring get pvc
```

PVC should be `Bound`.

### Access Prometheus

Add to your laptop's `/etc/hosts`:
```
192.168.1.10 prometheus.cluster.local
```

Then visit: **http://prometheus.cluster.local**
- Go to `/graph` to query metrics
- Check `/targets` to verify scraping is working

## Verification

In **Prometheus** (`/targets`), you should see:
- `kubernetes-nodes` — node metrics via API proxy
- `kubernetes-pods` — pod metrics
- `prometheus` — Prometheus itself

## Troubleshooting

### Pod stuck in `Init` or `Pending`

Check PVC binding:
```bash
kubectl -n monitoring describe pvc prometheus-storage-prometheus-0
kubectl -n monitoring describe pod prometheus-0
```

If PVC is stuck, Longhorn may not have capacity:
```bash
kubectl top nodes
```

### Can't reach http://prometheus.cluster.local

Verify Ingress:
```bash
kubectl -n monitoring get ingress
```

Ensure `/etc/hosts` is updated or DNS is configured.

### Memory usage too high

Check actual usage:
```bash
kubectl top pods -n monitoring
```

If >200MB, reduce retention in ConfigMap:
```bash
kubectl -n monitoring edit configmap prometheus-config
```

Change `retention.time` from `7d` to `3d` or `scrape_interval` from `30s` to `60s`.

## Resource Budget

| Component | CPU Request | Memory Request |
|-----------|------------|----------------|
| Prometheus | 50m | 64Mi |

Impact: **~0.05% CPU, 0.05% memory** (minimal overhead).
