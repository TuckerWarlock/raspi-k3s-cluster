# cluster/monitoring/

Monitoring stack: [VictoriaMetrics single-node](https://docs.victoriametrics.com/helm/victoria-metrics-single/),
deployed by the ArgoCD Application `cluster/argocd/addons/victoria-metrics.yaml` with values from
`victoria-metrics/values.yaml`.

- Runs on pi4controller (128Mi request / 256Mi limit), 14-day retention, 5Gi local-path PVC (USB drive).
- Uses the chart's built-in scrape config: API server, kubelet, cAdvisor, and any pod/service annotated
  `prometheus.io/scrape: "true"`.
- UI: `https://vm.cluster.local/vmui` (PromQL/MetricsQL).

Alerting: [vmalert + Alertmanager](https://docs.victoriametrics.com/helm/victoria-metrics-alert/),
deployed by `cluster/argocd/addons/vmalert.yaml` with rules and routing in `vmalert/values.yaml`.
Alerts go to the ntfy topic `cluster-status`; the rule list is in
[memory-management.md → Alerting](../../bootstrap/docs/memory-management.md#alerting).

No node-exporter yet. The Pi Zeros don't have the memory to spare; cAdvisor covers container memory and CPU.
The old Prometheus/Loki/Promtail manifests are in git history (`git show d8cf5eb^`).

See [architecture.md](../../bootstrap/docs/architecture.md) for design decisions.
