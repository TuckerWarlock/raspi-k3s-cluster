# cluster/docs/addons/

Documentation for cluster addon services managed by ArgoCD.

## Services

- **[metallb.md](metallb.md)** — Load balancer (Layer 2 advertisement, IP pools)
- **[traefik.md](traefik.md)** — Ingress controller (routing, TLS termination)
- **[longhorn.md](longhorn.md)** — Distributed block storage (PersistentVolumes)
- **[prometheus.md](prometheus.md)** — Prometheus metrics collection
- **[grafana.md](grafana.md)** — Grafana dashboards and visualization

## Deployment

See [cluster/argocd/README.md](../../cluster/argocd/README.md) for ArgoCD-based deployment.

All addons are deployed via Applications in `cluster/argocd/addons/`:

```bash
# Bootstrap (one-time)
helmfile sync

# Deploy all cluster infrastructure
kubectl apply -f cluster/argocd/root-application.yaml
```

ArgoCD will automatically deploy all services and keep them in sync with Git.
