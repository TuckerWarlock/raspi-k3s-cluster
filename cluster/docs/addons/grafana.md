# Grafana Dashboards

Deploy **Grafana** for visualizing Prometheus metrics and creating dashboards on the K3s cluster.

| Component | Deployment | Storage | Memory |
|-----------|-----------|---------|--------|
| Grafana | Deployment on pi4controller | Longhorn PVC (1 GB) | 25m / 32Mi |

## Architecture

- **Grafana Deployment** — pre-configured Prometheus datasource
- **Exposed via Traefik Ingress** on `grafana.cluster.local`
- **Persistent storage** for dashboards and configuration
- **Pre-configured Prometheus datasource** — ready to query

## Prerequisites

- K3s cluster running
- MetalLB configured
- Traefik ingress controller deployed
- **Longhorn storage** with working PVCs
- **Prometheus** deployed (in monitoring namespace)

## Installation

### Deploy Grafana

Via ArgoCD (recommended):
```bash
kubectl apply -f cluster/argocd/root-application.yaml
# ArgoCD will deploy Grafana automatically
```

Manual deployment:
```bash
kubectl apply -k cluster/monitoring/grafana/
```

### Verify deployment

```bash
kubectl -n monitoring get pods -w
```

Wait for Grafana pod to be `Running` (should be instant).

Check storage:
```bash
kubectl -n monitoring get pvc
```

PVC should be `Bound`.

### Access Grafana

Add to your laptop's `/etc/hosts`:
```
192.168.1.10 grafana.cluster.local
```

Then visit: **http://grafana.cluster.local**
- **Login:** `admin` / `admin`
- **Change password** for production use

## Verification

### Check Prometheus datasource

1. Go to **Configuration** (gear icon) → **Data Sources**
2. Click **Prometheus**
3. Verify **Status: OK** (green checkmark)

### Import dashboards

1. Go to **Dashboards** → **Browse**
2. Create a new dashboard or import from [Grafana Dashboard Library](https://grafana.com/grafana/dashboards)
3. Example queries:
   - `up` — show which targets are up
   - `node_cpu_seconds_total` — node CPU metrics
   - `container_memory_usage_bytes` — container memory

### Create custom dashboards

1. Click **Create** → **Dashboard** (or **+**)
2. **Add Panel** → Select **Prometheus** datasource
3. Enter PromQL queries (e.g., `up`, `rate(container_cpu_usage_seconds_total[5m])`)

## Troubleshooting

### Datasource shows "Health: Server Error"

Verify Prometheus is running and reachable:
```bash
kubectl -n monitoring get pod -l app=prometheus
kubectl -n monitoring logs prometheus-0
```

Try port-forward to test:
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then: curl http://localhost:9090/-/healthy
```

### Can't reach http://grafana.cluster.local

Verify Ingress:
```bash
kubectl -n monitoring get ingress
```

Ensure `/etc/hosts` is updated or DNS is configured.

### Login credentials not working

Default credentials are `admin` / `admin`. If changed, check the Grafana pod:
```bash
kubectl -n monitoring logs -l app=grafana
```

To reset, delete the Grafana pod (will restart with defaults):
```bash
kubectl -n monitoring delete pod -l app=grafana
```

### Memory usage too high

Check actual usage:
```bash
kubectl top pods -n monitoring
```

If >100MB, consider reducing dashboard update frequency or number of active dashboards.

## Resource Budget

| Component | CPU Request | Memory Request |
|-----------|------------|----------------|
| Grafana | 25m | 32Mi |

Impact: **~0.01% CPU, 0.02% memory** (minimal overhead).
