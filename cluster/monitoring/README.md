# cluster/monitoring/

Monitoring stack — currently not deployed to conserve memory on pi4controller for AI inference workloads (Monday/Ollama).

The `namespace.yaml` is retained so the namespace can be recreated if monitoring is re-enabled in the future.

## Re-enabling Monitoring

To bring back Prometheus + Loki + Promtail, restore the ArgoCD Application manifests in `cluster/argocd/addons/` and the corresponding manifests in `cluster/monitoring/prometheus/`, `loki/`, and `promtail/` from git history.

See [architecture.md](../../bootstrap/docs/architecture.md) for design decisions.
