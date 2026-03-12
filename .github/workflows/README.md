# GitHub Action workflows

Use these as reference:
- https://spacelift.io/blog/github-actions-kubernetes
- https://citizix.com/how-to-deploy-with-argocd-using-github-actions-and-helm-templating/

## helm-validate.yml

Validation-only CI workflow for Helm charts and values in this repository.
It does not connect to a cluster and does not deploy anything.

### What it validates

1. Installs Helm in the runner
2. Adds and updates chart repos:
	- `traefik` (`https://traefik.github.io/charts`)
	- `longhorn` (`https://charts.longhorn.io`)
3. Pulls both charts locally to `/tmp/charts` for linting
4. Installs kubeconform for schema validation of rendered output
5. Lints Traefik chart using repo values:
	- `manifests/traefik/values.yaml`
6. Renders Traefik templates and fails if output is empty
7. Renders Longhorn templates with cluster-specific overrides and fails if output is empty
8. Runs kubeconform against both rendered files in strict mode (with missing schema ignores for non-core resources)

### Trigger conditions

- `pull_request` to `main` when changes affect:
  - `charts/**`
  - `manifests/**`
  - `.github/workflows/helm-validate.yml`
- `workflow_dispatch` for manual runs

### Why this exists

- Catches Helm syntax/template regressions early
- Adds Kubernetes API schema checks on rendered manifests
- Verifies repository values continue to render cleanly
- Keeps CI focused on validation while deployment remains a separate/manual concern
