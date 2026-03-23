# GitHub Workflows

This directory contains validation-only CI workflows. They do not connect to a live cluster and do not deploy anything.

## Files

- `helm-validate.yml`
	- Entry workflow for pull requests and manual runs.
	- Defines two jobs:
		- `helm_validate` (schema validation)
		- `pluto_validate` (API deprecation validation)
	- Calls the reusable workflow for both jobs.

- `reusable-manifest-validation.yml`
	- Reusable workflow containing shared setup and validation logic.
	- Accepts inputs:
		- `validator`: `kubeconform` or `pluto`
		- `k8s_target_version`: target Kubernetes version for Pluto checks

## Validation Flow

1. Checkout repository.
2. Install `helmfile` via `helmfile/helmfile-action`.
3. Render all Helm releases from `helmfile.yaml` using `helmfile template > /tmp/all-rendered.yaml`.
4. For `kubeconform` job:
	 - Install tools using `yokawasa/action-setup-kube-tools`.
	 - Validate raw manifests under `cluster/` (excluding `values.yaml`).
	 - Validate rendered Helm manifests in strict mode.
5. For `pluto` job:
	 - Install Pluto using `FairwindsOps/pluto/github-action@master`.
	 - Check both raw manifests and rendered manifests for deprecated/removed APIs.

## Trigger Conditions

`helm-validate.yml` runs on:

- `pull_request` to `main` when files change in:
	- `cluster/**`
	- `bootstrap/scripts/install-argocd.sh`
	- `.github/workflows/helm-validate.yml`
	- `.github/workflows/reusable-manifest-validation.yml`
- `workflow_dispatch` for manual runs

## Version Pinning

- Prefer major-version pins for GitHub Actions where available.
- Some actions may require full tag pins when a major alias is not published.

## Why This Exists

- Catch rendering and schema regressions early.
- Detect Kubernetes API deprecations before cluster upgrades.
- Keep CI portable as new Helm releases are added by updating `helmfile.yaml` only.
