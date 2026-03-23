# cluster/

Kubernetes infrastructure-as-code (IaC) managed by ArgoCD.

This directory contains all manifests and Helm releases for the cluster. Changes here are automatically synced to the running cluster via ArgoCD.

## Structure

- **core-system/** — Core infrastructure deployed via [helmfile.yaml](../helmfile.yaml):
  - `metallb/` — Load balancer (helmfile release)
  - `traefik/` — Ingress controller (helmfile release)
  - `longhorn/` — Distributed storage (helmfile release)

- **argocd/** — GitOps management (helmfile release):
  - Application definitions that auto-sync this repo

- **monitoring/** — Prometheus + Grafana (kubectl apply):
  - StatefulSets, ConfigMaps, RBAC, Ingress
  - See [bootstrap/docs/08-prometheus-grafana-monitoring.md](../bootstrap/docs/08-prometheus-grafana-monitoring.md)

## Deployment Workflow

**Core infrastructure** (MetalLB, Traefik, Longhorn, ArgoCD):
```bash
helmfile sync
```

**Monitoring** (Prometheus + Grafana):
```bash
kubectl apply -f cluster/monitoring/
```

**User workloads** (via ArgoCD):
- Create manifests in `workloads/` (or elsewhere)
- Add an Application CRD to `argocd/` pointing to your workload path
- ArgoCD auto-syncs

## Adding Helm Releases

To add a new Helm release:

1. Add repo and release definition to [helmfile.yaml](../helmfile.yaml)
2. Create a values file: `cluster/<service>/values.yaml`
3. Run `helmfile sync`
4. Commit changes

## Adding Raw Manifests

To add raw Kubernetes manifests:

1. Create directory: `cluster/<namespace>/<component>/`
2. Add manifests (namespace, deployment, service, etc.)
3. Run validation: `bash local_ci.sh`
4. Deploy: `kubectl apply -f cluster/<namespace>/<component>/`
5. Commit changes

## Validation

All manifests are validated on pull request:
- Schema validation with `kubeconform`
- API deprecation checks with `Pluto`
- Helm rendering with `helmfile template`

See [.github/workflows/README.md](../.github/workflows/README.md) for details.
