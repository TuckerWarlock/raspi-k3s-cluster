# cluster/monitoring/

Lightweight Prometheus monitoring stack.

See [cluster/argocd/addons/docs/prometheus.md](../argocd/addons/docs/prometheus.md) for complete setup instructions.

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
└── README.md
```

## Deployment

Managed by ArgoCD Applications:
- `cluster/argocd/addons/prometheus.yaml` → deploys prometheus/ via Kustomization

Manual deployment:
```bash
kubectl apply -k cluster/monitoring/prometheus/
```

Verify:
```bash
kubectl -n monitoring get pods -w
kubectl -n monitoring get svc
kubectl -n monitoring get ingress
```

Access:
- **Prometheus**: http://prometheus.cluster.local

## Resource Usage

| Component | CPU | Memory |
|-----------|-----|--------|
| Prometheus | 50m | 64Mi |

## Architecture

- **Prometheus StatefulSet** — minimal, no operator overhead
- **7-day data retention** — tunable via ConfigMap
- **30-second scrape interval** — essential metrics only
- **Node pinning** — runs only on pi4controller
- **Longhorn storage** — 3GB for Prometheus

See [architecture.md](../../bootstrap/docs/architecture.md) for design decisions.
