# Step 08: Prometheus + Grafana Monitoring

## Overview

Deploy the **Prometheus + Grafana** monitoring stack on the K3s cluster.

| Component | Deployment | Storage |
|-----------|-----------|---------|
| Prometheus | pi4controller | Longhorn PVC (10 GB, 15-day retention) |
| Prometheus Operator | pi4controller | — |
| Grafana | pi4controller | Longhorn PVC (2 GB) |
| Node Exporter | DaemonSet on all nodes | — |
| kube-state-metrics | pi4controller | — |

## Architecture

- **Prometheus Operator** manages the Prometheus server via `Prometheus` CRD
- **ServiceMonitor** objects (auto-generated) tell Prometheus what to scrape
- **Node Exporter** DaemonSet collects OS-level metrics (CPU, memory, disk, network)
- **kube-state-metrics** exposes Kubernetes object state (pods, deployments, etc.)
- **Grafana** queries Prometheus and visualizes dashboards
- Both Prometheus and Grafana are exposed via **Traefik Ingress** on `prometheus.cluster.local` and `grafana.cluster.local`

## Prerequisites

- K3s cluster running (steps 01–03)
- MetalLB configured (step 04)
- Traefik ingress controller deployed (step 05)
- **Longhorn storage** with working PVCs (step 06)

## Installation

### Step 1: Update Helm repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Step 2: Deploy via Helmfile

The `kube-prometheus-stack` release is now in `helmfile.yaml`. Deploy it:

```bash
helmfile sync
```

This will:
1. Create the `monitoring` namespace
2. Deploy Prometheus Operator + Prometheus server (pinned to pi4controller)
3. Deploy Grafana with Longhorn persistence (pinned to pi4controller)
4. Deploy Node Exporter as a DaemonSet (all nodes)
5. Deploy kube-state-metrics on pi4controller
6. Apply the Ingress for Prometheus and Grafana

### Step 3: Verify the deployment

Check pod status:

```bash
kubectl -n monitoring get pods -o wide
```

Expected output:
```
NAME                                          READY   STATUS    RESTARTS   NODE
kube-prometheus-stack-grafana-xxxxx           1/1     Running   0          pi4controller
kube-prometheus-stack-prometheus-operator-xxx 1/1     Running   0          pi4controller
prometheus-kube-prometheus-prometheus-0       2/2     Running   0          pi4controller
node-exporter-xxxxx                           1/1     Running   0          p1
node-exporter-yyyyy                           1/1     Running   0          p2
node-exporter-zzzzz                           1/1     Running   0          p3
node-exporter-wwwww                           1/1     Running   0          p4
kube-state-metrics-xxxxx                      1/1     Running   0          pi4controller
```

Check PVC binding:

```bash
kubectl -n monitoring get pvc
```

Both `prometheus-kube-prometheus-prometheus-0` and `kube-prometheus-stack-grafana` should be `Bound`.

### Step 4: Access the dashboards

From your laptop, edit `/etc/hosts`:

```
192.168.1.10 prometheus.cluster.local grafana.cluster.local
```

Or add DNS records if using a local DNS server.

Then visit:
- **Prometheus**: http://prometheus.cluster.local → `/graph` for PromQL queries
- **Grafana**: http://grafana.cluster.local → Login with `admin` / `admin` (change password!)

### Step 5: Verify metrics collection

In **Prometheus** (`/targets`), you should see:
- `kubernetes-nodes` (Node Exporter on all nodes)
- `kubernetes-pods` (Pod metrics)
- `prometheus-operator` (Prometheus itself)

In **Grafana**:
- The Prometheus datasource is pre-configured
- Go to **Dashboards** → **Browse** to see available dashboards
- Popular ones: "Kubernetes Cluster Monitoring", "Node Exporter Full"

## Troubleshooting

### Prometheus not scraping metrics

Check ServiceMonitor objects:

```bash
kubectl -n monitoring get servicemonitor
```

If none exist, Prometheus won't find targets. The Helm chart should auto-create them.

### Node Exporter pods in CrashLoopBackOff

Check logs:

```bash
kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus-node-exporter
```

Common issue: Pi Zero nodes are under-resourced. Reduce CPU/memory requests if needed.

### Grafana datasource shows "Health: Server Error"

Check that Prometheus is running:

```bash
kubectl -n monitoring get pod -l app.kubernetes.io/name=prometheus
```

If stuck in `Init:0/1` or `Pending`, check PVC:

```bash
kubectl -n monitoring describe pvc prometheus-kube-prometheus-prometheus-0
```

If PVC is stuck `Pending`, Longhorn may not have capacity. Check:

```bash
kubectl -n longhorn-system get storageclass
kubectl -n longhorn-system get pvc
```

### Can't reach http://prometheus.cluster.local

Verify Ingress:

```bash
kubectl -n monitoring get ingress
```

If `HOSTS` are empty or `STATUS` is `<pending>`, check Traefik:

```bash
kubectl -n traefik get svc traefik
```

Ensure the `EXTERNAL-IP` is within the MetalLB pool (192.168.1.241–254).

## Next Steps

- **Step 09**: Deploy **Loki + Promtail** for centralized log aggregation
- **Step 10**: Deploy a sample workload to validate the full GitOps pipeline
- **Step 11**: Configure **Longhorn backup strategy** for disaster recovery

## Notes

- **Grafana admin password**: Stored in `prometheus-values.yaml` under `grafana.adminPassword`. Change it in production!
- **Prometheus retention**: Set to 15 days via `retention: 15d`. Adjust in `prometheus-values.yaml` if needed.
- **Resource limits**: Pi 4 gets 500m CPU / 512 MB RAM for Prometheus; 200m CPU / 256 MB RAM for Grafana. Monitor metrics to ensure these are sufficient.
