# cluster/monitoring/

Lightweight Prometheus + Grafana monitoring stack.

See [bootstrap/docs/08-prometheus-grafana-monitoring.md](../../bootstrap/docs/08-prometheus-grafana-monitoring.md) for complete setup instructions.

## Files

- `namespace.yaml` — Monitoring namespace
- `prometheus-config.yaml` — Prometheus scrape configuration (ConfigMap)
- `prometheus-rbac.yaml` — ServiceAccount, ClusterRole, ClusterRoleBinding
- `prometheus-statefulset.yaml` — Prometheus StatefulSet + Services + PVC
- `grafana.yaml` — Grafana Deployment with provisioned Prometheus datasource + PVC
- `ingress.yaml` — Traefik Ingress routes (prometheus.cluster.local, grafana.cluster.local)

## Deployment

Deploy all manifests:
```bash
kubectl apply -f cluster/monitoring/
```

Verify:
```bash
kubectl -n monitoring get pods -w
kubectl -n monitoring get svc
kubectl -n monitoring get ingress
```

Access dashboards:
- **Prometheus**: http://prometheus.cluster.local
- **Grafana**: http://grafana.cluster.local (default: admin / admin)

## Resource Usage

| Component | CPU | Memory |
|-----------|-----|--------|
| Prometheus | 50m | 64Mi |
| Grafana | 25m | 32Mi |
| **Total** | **75m** | **96Mi** |

## Architecture

- **Prometheus StatefulSet** — minimal, no operator overhead
- **7-day data retention** — tunable via ConfigMap
- **30-second scrape interval** — essential metrics only
- **Node pinning** — runs only on pi4controller
- **Longhorn storage** — 3GB for Prometheus, 1GB for Grafana

See [architecture.md](../../bootstrap/docs/architecture.md) for design decisions.
