# 07 — ArgoCD (GitOps Management)

ArgoCD is the GitOps controller for this cluster. After bootstrapping it manages itself and
all other workloads from the Git repository — any push to `main` is automatically applied to
the cluster.

## Prerequisites

- K3s server and agents running (steps 01–03)
- MetalLB pool applied (step 04)
- Traefik running with an external IP (step 05)
- Longhorn running (step 06)
- Laptop `/etc/hosts` updated with `argocd.cluster.local` pointing to the Traefik external IP

## Step 1 — Install ArgoCD via helmfile

If you ran `helmfile sync` in step 04, ArgoCD is already installed. Verify:

```bash
kubectl -n argocd get pods
```

If helmfile has not been run yet:

```bash
cd ~/raspi-k3s-cluster
helmfile sync
```

## Step 2 — Apply the ArgoCD Ingress

The Ingress resource that exposes `argocd.cluster.local` is a raw manifest and is not part of
the Helm chart. Apply it manually:

```bash
kubectl apply -f cluster/argocd/argocd-ingress.yaml
```

Verify it was created:

```bash
kubectl -n argocd get ingress
# Expected: argocd-server with HOST argocd.cluster.local
```

> **Why `server.insecure: true`?**
> ArgoCD server defaults to forcing HTTP → HTTPS redirects internally. When Traefik
> terminates TLS at the ingress layer and proxies plain HTTP to the backend, this creates
> a redirect loop. Setting `configs.params.server.insecure: true` in `argocd-values.yaml`
> disables ArgoCD's internal redirect so Traefik handles all TLS negotiation.

## Step 3 — Access the ArgoCD UI

Open https://argocd.cluster.local in your browser. Accept the self-signed certificate warning
(Traefik uses a default self-signed cert until cert-manager is configured).

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo   # add newline
```

Login with username `admin` and the password above.

> **Change the password** after first login: Settings → User Info → Update Password.

## Step 4 — Bootstrap the App of Apps

Apply the root Application CRD once. This tells ArgoCD to watch `cluster/argocd/addons/`
and automatically deploy everything defined there:

```bash
kubectl apply -f cluster/argocd/root-application.yaml
```

ArgoCD will now auto-sync and deploy:
- Prometheus (`cluster/monitoring/prometheus/`)
- Grafana (`cluster/monitoring/grafana/`)

Watch the sync in the UI or via CLI:

```bash
kubectl -n argocd get applications
# Expected: cluster-addons Synced Healthy
```

## GitOps workflow (ongoing)

From this point forward, the cluster is fully GitOps-managed:

1. Make a change to a manifest in `cluster/`
2. Commit and push to `main`
3. ArgoCD detects the drift within ~3 minutes
4. The cluster auto-syncs to match Git

To force an immediate sync:

```bash
# Via kubectl
kubectl -n argocd patch application cluster-addons \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Or click "Sync" in the ArgoCD UI
```

## Adding new workloads

To deploy an application via GitOps:

1. Add manifests to `cluster/workloads/<app-name>/`
2. Create an Application CRD in `cluster/argocd/workloads/<app-name>.yaml`
3. Add the filename to `cluster/argocd/workloads/kustomization.yaml`
4. Commit and push — ArgoCD picks it up automatically

See `cluster/argocd/README.md` for a full example Application CRD.

## Troubleshooting

**UI returns a redirect loop or blank page**

ArgoCD server is not in insecure mode. Verify the Helm values:

```bash
helm -n argocd get values argocd | grep insecure
# Expected: server.insecure: true
```

If missing, upgrade with the correct values:

```bash
helm -n argocd upgrade argocd argo/argo-cd --version 7.8.1 \
  --values cluster/argocd/argocd-values.yaml
```

**`argocd.cluster.local` not resolving**

Verify Traefik has an external IP and `/etc/hosts` on your laptop is correct:

```bash
kubectl -n traefik get svc traefik
# EXTERNAL-IP must not be <pending>
```

**Application stuck in `OutOfSync` or `Degraded`**

```bash
kubectl -n argocd describe application cluster-addons
kubectl -n argocd get events --sort-by='.lastTimestamp'
```

Check that the `repoURL` in `root-application.yaml` matches your actual GitHub repository URL.

**Can't log in — forgot password**

Reset it by deleting the initial secret (causes ArgoCD to regenerate it on restart) or use
the CLI:

```bash
# Port-forward if ingress isn't accessible
kubectl port-forward -n argocd svc/argocd-server 8080:80

argocd login localhost:8080 --username admin --password <current-pw>
argocd account update-password
```
