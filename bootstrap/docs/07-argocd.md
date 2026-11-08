# 07 — ArgoCD (GitOps Management)

> Reference guide. Bootstrap steps are in [rebuild.md](rebuild.md#phase-3--argocd-and-the-apps),
> steps 3.3–3.4 and 3.7.

ArgoCD deploys and manages everything in the cluster except itself. Any push to `main` is
applied automatically (`automated` sync with `prune` and `selfHeal` on every app).

## How it's deployed

- **ArgoCD itself:** `helmfile sync` installs the `argo/argo-cd` chart (version pinned in
  `helmfile.yaml`) with `cluster/argocd/argocd-values.yaml`. This is the only Helm release
  helmfile manages.
- **Everything else:** `kubectl apply -f cluster/argocd/root-application.yaml` creates the
  `cluster-addons` app, which manages:

```
cluster/argocd/
├── root-application.yaml        # cluster-addons → watches addons/
└── addons/
    ├── metallb.yaml             # Helm chart
    ├── metallb-config.yaml      # cluster/core-system/metallb/config/
    ├── traefik.yaml             # Helm chart
    ├── victoria-metrics.yaml    # Helm chart (OCI)
    ├── argocd-config.yaml       # cluster/argocd/config/ — ArgoCD ingress + OCI repo secret
    └── workloads.yaml           # → watches cluster/argocd/workloads/
                                 #     └── gatus.yaml → workloads/gatus/
```

Helm-chart apps use two sources: the upstream chart, plus this repo as `$values` so the
values file lives in Git.

## Component placement

| Component | Node | Why |
|---|---|---|
| application-controller | `pi4controller` | 512Mi limit — a Pi Zero's entire RAM |
| server, repo-server, redis | Pi Zeros (`node-role.kubernetes.io/worker`) | Keeps the controller's memory free |
| notifications, applicationset | disabled | Unused |

The server's probes start after 60s because the Zeros are slow to start it.

## Settings worth knowing

| Setting | Why |
|---|---|
| `server.insecure: true` | Traefik terminates TLS. Without this, ArgoCD redirects HTTP→HTTPS itself and loops |
| `timeout.reconciliation: 300s` | Checks Git every 5 minutes (default 3) to cut churn on the controller |
| `controller.status/operation.processors: 5 / 3` | Fewer workers, less memory, for ~8 apps |
| `accounts.admin: apiKey,login` | Lets the admin account create API tokens |

## Adding a workload

1. Put the manifests and a `kustomization.yaml` in `workloads/<app>/` (see `workloads/gatus/`).
2. Copy `cluster/argocd/workloads/gatus.yaml` to `cluster/argocd/workloads/<app>.yaml` and
   change `name`, `path`, and `destination.namespace`.
3. Add `<app>.yaml` to `cluster/argocd/workloads/kustomization.yaml`.
4. Run `./local_ci.sh`, then push. Deploy one app at a time —
   [memory-management.md → Safe Deployment Procedure](memory-management.md#safe-deployment-procedure).

## Never delete an app to "reset" it

Deleting an Application in the ArgoCD UI or CLI (default: *foreground* cascade) deletes
**everything it manages** — namespace, PVCs, and any Secrets you created by hand in that
namespace. For ntfy that wipes its users and tokens and the `ntfy-tls` cert; for Gatus and
VictoriaMetrics it wipes their history.

- To re-sync: refresh (`argocd.argoproj.io/refresh=hard`) or **Sync** in the UI.
- To hand a hand-applied app over to `main` (as after testing from a branch): do nothing —
  the `workloads` app adopts an Application with the same name on its next sync.
- If you really must remove the Application but keep its resources, use the UI's
  **Non-cascading** delete option.

## Day-to-day commands

```bash
kubectl -n argocd get applications                              # status of everything
kubectl -n argocd annotate app <app> argocd.argoproj.io/refresh=normal --overwrite   # re-check Git now
kubectl -n argocd annotate app <app> argocd.argoproj.io/refresh=hard --overwrite     # also re-render charts
kubectl -n argocd get app <app> -o jsonpath='{.status.conditions}{"\n"}{.status.operationState.message}{"\n"}'
```

Upgrade ArgoCD itself: bump `version:` in `helmfile.yaml` (check `argocd-values.yaml` keys
against `helm show values argo/argo-cd --version <new>`), push, then on the Pi
`git pull && helmfile sync`.

## Troubleshooting

**App `Unknown` with `field not declared in schema`**

ArgoCD is older than the cluster's Kubernetes and can't diff newer fields. K3s installs the
latest stable release, so this shows up after a rebuild. Upgrade the ArgoCD chart (above).

**App `Unknown` with `context deadline exceeded`**

The repo-server (on a Pi Zero) didn't render the chart within 60s. A Helm repo whose
`index.yaml` is several MB takes over a minute to fetch on a Zero. Pull that chart from
its OCI registry instead — see `cluster/argocd/config/repo-victoriametrics-oci.yaml`.

**Sync fails with `Installing CRDs with version before v1.5.0 is prohibited`**

A chart is trying to install older Gateway API CRDs than the ones K3s ships. Upgrade that
chart to a version that doesn't bundle them (this is why Traefik is on 42.x).

**Sync keeps retrying an old revision after a fix was pushed**

An operation started before your push keeps retrying the revision it began with until its
retries run out (a few minutes); the next auto-sync then uses the new commit. Wait it out,
or terminate it in the UI (**App → Terminate**).

**App permanently `OutOfSync` but every sync says `unchanged`**

Large CRDs and client-side apply. Add `ServerSideApply=true` to the app's `syncOptions`
(as in `cluster/argocd/addons/traefik.yaml`).

**`argocd.cluster.local` doesn't load**

```bash
kubectl -n traefik get svc traefik          # EXTERNAL-IP 192.168.1.241?
kubectl -n argocd get ingress               # host argocd.cluster.local?
```

Then check the hostname resolves to `192.168.1.241` on this device
([rebuild.md 3.6](rebuild.md#36--resolve-the-hostnames)).

**Forgot the admin password**

Before you change it, it's in the `argocd-initial-admin-secret` secret
([rebuild.md 3.7](rebuild.md#37--log-in-to-argocd)). After, reset it with the `argocd` CLI:

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:80
argocd login localhost:8080 --username admin --plaintext
argocd account update-password
```
