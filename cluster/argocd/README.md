# cluster/argocd/

ArgoCD GitOps management with Kustomization organization.

## Structure

```
argocd/
├── kustomization.yaml          # Root Kustomization (includes all overlays)
├── namespace.yaml              # ArgoCD namespace
├── root-application.yaml       # Root Application CRD (deploys everything)
├── argocd-values.yaml          # Helm values for ArgoCD itself
├── argocd-ingress.yaml         # Ingress for ArgoCD server UI
├── addons/                     # System services on pi4controller
│   ├── kustomization.yaml
│   ├── metallb.yaml            # MetalLB Application
│   ├── traefik.yaml            # Traefik Application
│   ├── longhorn.yaml           # Longhorn Application
│   ├── prometheus.yaml         # Prometheus Application
│   ├── grafana.yaml            # Grafana Application
│   └── docs/                   # Setup documentation for each addon
│       ├── INDEX.md
│       ├── metallb.md
│       ├── traefik.md
│       ├── longhorn.md
│       ├── prometheus.md
│       └── grafana.md
└── workloads/                  # User applications (pi zero workers)
    ├── kustomization.yaml
    └── (add your apps here)
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
- **Longhorn** (storage manager on controller, CSI on all nodes)
- **Monitoring** (Prometheus + Grafana, pinned to pi4controller)

### Step 3: Monitor in ArgoCD UI

Access the dashboard:
```
https://argocd.cluster.local
```

Default credentials: `admin` / (get password from: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`)

## Adding User Workloads

Create your application in a new file under `workloads/`:

```yaml
# workloads/my-app.yaml
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

Then add to `workloads/kustomization.yaml`:

```yaml
resources:
- my-app.yaml
```

Commit and push. ArgoCD will auto-sync within seconds.

## Separation Strategy

- **addons/** — system infrastructure (MetalLB, Traefik, Longhorn, Prometheus, Grafana)
  - All pinned to `pi4controller` via nodeSelector
  - Resources reserved for cluster health
  
- **workloads/** — user applications
  - Deploy on pi zero workers (512MB RAM each)
  - Can use node-role labels for scheduling

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
