# 09 — Loki + Promtail (Log Aggregation)

## Overview

This step adds log aggregation to the cluster using:

- **Loki** — log storage and query engine (Grafana's Prometheus-for-logs); runs in single-process mode on `pi4controller`
- **Promtail** — log shipping agent; runs as a DaemonSet on every node, scraping container logs and forwarding them to Loki
- **Grafana** — updated with a Loki datasource so logs are queryable alongside metrics

All components are managed via ArgoCD and auto-sync from the `main` branch.

## Architecture

```
[pi4controller]  [p1] [p2] [p3] [p4]
  Loki :3100      Promtail DaemonSet
       ↑               |
       └───────────────┘  (push: /loki/api/v1/push)

  Grafana :3000 ──→ Loki :3100  (datasource query)
```

Log files are read directly from each node's host filesystem at:
`/var/log/pods/<namespace>_<pod>_<uid>/<container>/*.log`

## Files Created

| File | Description |
|------|-------------|
| `cluster/monitoring/loki/loki-configmap.yaml` | Loki config: single-process mode, filesystem storage, 7-day retention |
| `cluster/monitoring/loki/loki-statefulset.yaml` | StatefulSet + headless + ClusterIP Services |
| `cluster/monitoring/loki/kustomization.yaml` | Kustomize entry point for loki |
| `cluster/monitoring/promtail/promtail-daemonset.yaml` | RBAC + ConfigMap + DaemonSet |
| `cluster/monitoring/promtail/kustomization.yaml` | Kustomize entry point for promtail |
| `cluster/argocd/addons/loki.yaml` | ArgoCD Application CRD |
| `cluster/argocd/addons/promtail.yaml` | ArgoCD Application CRD |

## Files Modified

| File | Change |
|------|--------|
| `cluster/monitoring/grafana/grafana.yaml` | Added Loki datasource to `grafana-datasource` ConfigMap |
| `cluster/argocd/addons/kustomization.yaml` | Added `loki.yaml` and `promtail.yaml` |

## Deploying

ArgoCD auto-syncs on push to `main` — no manual steps needed. To watch rollout:

```bash
# Watch Loki come up
kubectl rollout status statefulset/loki -n monitoring

# Watch Promtail DaemonSet
kubectl rollout status daemonset/promtail -n monitoring

# Check all monitoring pods
kubectl get pods -n monitoring
```

Expected pod list after deploy:

```
NAME                       READY   STATUS    RESTARTS
grafana-xxx                1/1     Running
loki-0                     1/1     Running
prometheus-0               1/1     Running
promtail-xxxxx (×5)        1/1     Running   ← one per node
```

## Verifying Logs in Grafana

1. Open `http://grafana.cluster.local` (or `http://192.168.1.241:3000` via MetalLB)
2. Go to **Explore** (compass icon in left sidebar)
3. Select the **Loki** datasource from the dropdown
4. Run a basic query: `{namespace="monitoring"}`
5. You should see log lines from Prometheus, Grafana, Loki, and Promtail itself

### Useful LogQL queries

```logql
# All logs from a namespace
{namespace="kube-system"}

# Logs from a specific pod
{pod="prometheus-0"}

# Filter for errors
{namespace="monitoring"} |= "error"

# Loki's own logs (self-monitoring)
{pod=~"loki-.*"}
```

## Loki Storage

Loki stores data on a 3Gi Longhorn PVC (`storage-loki-0`) with:
- **Retention:** 7 days (enforced by the compactor)
- **Index:** TSDB v13 with 24h periods
- **Chunks:** filesystem storage at `/loki/chunks`

## Troubleshooting

### Loki not starting
```bash
kubectl logs -n monitoring loki-0
kubectl describe pod -n monitoring loki-0
```

Common issues:
- PVC not bound (check Longhorn) → `kubectl get pvc -n monitoring`
- ConfigMap schema errors → validate YAML indentation in `loki-configmap.yaml`

### Promtail not shipping logs
```bash
# Check promtail on a specific node
kubectl logs -n monitoring -l app=promtail --field-selector spec.nodeName=pi4controller

# Check if Loki is reachable
kubectl exec -n monitoring -l app=promtail -- wget -qO- http://loki:3100/ready
```

### Grafana can't connect to Loki
In Grafana → Connections → Data Sources → Loki → click **Test**. If it fails, verify `loki` ClusterIP Service is present:
```bash
kubectl get svc -n monitoring loki
```

## Resource Usage

| Component | CPU request/limit | Memory request/limit | Nodes |
|-----------|------------------|----------------------|-------|
| Loki | 50m / 200m | 64Mi / 256Mi | pi4controller |
| Promtail | 10m / 50m | 32Mi / 64Mi | all 5 nodes |
