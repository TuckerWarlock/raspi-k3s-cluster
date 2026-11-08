# cluster/argocd/

ArgoCD GitOps management with Kustomization organization.

## Structure

```
argocd/
├── kustomization.yaml          # Root Kustomization (includes all overlays)
├── namespace.yaml              # ArgoCD namespace
├── root-application.yaml       # Root Application CRD (deploys everything)
├── argocd-values.yaml          # Helm values for ArgoCD itself
├── config/                     # ArgoCD ingress + VictoriaMetrics OCI repo secret
├── addons/                     # System services on pi4controller
│   ├── kustomization.yaml
│   ├── metallb.yaml            # MetalLB Application
│   ├── metallb-config.yaml     # IPAddressPool + L2Advertisement
│   ├── traefik.yaml            # Traefik Application
│   ├── victoria-metrics.yaml   # VictoriaMetrics Application
│   ├── argocd-config.yaml      # → config/
│   ├── workloads.yaml          # App-of-apps for workloads/
│   └── docs/INDEX.md
└── workloads/                  # User applications (pi zero workers)
    ├── kustomization.yaml
    └── gatus.yaml              # → workloads/gatus/ at the repo root
```

## Deployment

### Step 1: Bootstrap ArgoCD (one-time, manual)

```bash
# From pi4controller
helmfile sync
```

This deploys ArgoCD itself.

### Step 2: Deploy the cluster (one-time)

```bash
# Apply the root Application CRD
kubectl apply -f cluster/argocd/root-application.yaml
```

This creates the root Application, which includes all controller-addons and workloads via Kustomization.

ArgoCD will automatically deploy:
- **MetalLB** (speaker pinned to pi4controller)
- **Traefik** (ingress, pinned to pi4controller)
- **VictoriaMetrics** (metrics, pinned to pi4controller)
- **Gatus** (status page, via the `workloads` app)

### Step 3: Monitor in ArgoCD UI

Access the dashboard:
```
https://argocd.cluster.local
```

Default credentials: `admin` / (get password from: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`)

## Adding User Workloads

Put the manifests in `workloads/my-app/` at the repo root, then create the Application in
`cluster/argocd/workloads/` (copy `gatus.yaml`):

```yaml
# cluster/argocd/workloads/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/TuckerWarlock/raspi-k3s-cluster
    path: workloads/my-app    # Create manifests at workloads/my-app/
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: default        # Or your namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Then add it to `cluster/argocd/workloads/kustomization.yaml`:

```yaml
resources:
- my-app.yaml
```

Run `./local_ci.sh`, commit, and push. ArgoCD picks it up within 5 minutes. Full steps:
[07-argocd.md → Adding a workload](../../bootstrap/docs/07-argocd.md#adding-a-workload).

## Separation Strategy

- **addons/** — system infrastructure (MetalLB, Traefik, VictoriaMetrics)
  - All pinned to `pi4controller` via nodeSelector
  - Resources reserved for cluster health
  
- **workloads/** — user applications
  - Prefer the Pi Zero workers (`node-role.kubernetes.io/worker` nodeSelector, 512MB RAM each)
  - Pin to `pi4controller` only if the app needs the LAN or a USB-backed PVC (e.g. Gatus)

## GitOps Workflow

```
1. Modify manifest in Git (or add new Application)
2. Commit and push to main
3. ArgoCD detects drift
4. Cluster syncs automatically (or via "Sync" button in UI)
5. View progress in ArgoCD dashboard
```

## Troubleshooting

### See all Applications:
```bash
kubectl get applications -n argocd
```

### Check Application status:
```bash
kubectl describe application -n argocd <app-name>
```

### View app resources:
```bash
kubectl get all -n <namespace>
```

### Manual sync (if auto-sync is disabled):
```bash
# Via CLI
argocd app sync <app-name>

# Via UI: click "Sync" button on the Application
```
