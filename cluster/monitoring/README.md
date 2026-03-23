# cluster/monitoring/

Lightweight Prometheus + Grafana monitoring stack.

See [cluster/argocd/addons/docs/prometheus.md](../argocd/addons/docs/prometheus.md) and [cluster/argocd/addons/docs/grafana.md](../argocd/addons/docs/grafana.md) for complete setup instructions.

## Structure

```
monitoring/
├── namespace.yaml    # Shared monitoring namespace
├── prometheus/       # Prometheus StatefulSet
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── prometheus-rbac.yaml
│   ├── prometheus-config.yaml
│   └── prometheus-statefulset.yaml
├── grafana/          # Grafana Deployment
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── grafana.yaml
└── README.md
```

## Deployment

Managed by ArgoCD Applications:
- `cluster/argocd/addons/prometheus.yaml` → deploys prometheus/ via Kustomization
- `cluster/argocd/addons/grafana.yaml` → deploys grafana/ via Kustomization

Manual deployment:
```bash
kubectl apply -k cluster/monitoring/prometheus/
kubectl apply -k cluster/monitoring/grafana/
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
