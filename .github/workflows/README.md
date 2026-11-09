# GitHub Workflows

This directory contains validation-only CI workflows. They do not connect to a live cluster and do not deploy anything.

## Files

- `shellcheck.yml`
	- Lints all shell scripts in `bootstrap/scripts/` and `local_ci.sh` with ShellCheck.
	- Catches real bugs: unquoted variables, incorrect redirects, unsafe patterns.
	- Runs at `--severity=warning` (warnings + errors; style notes suppressed).

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

### ShellCheck (`shellcheck.yml`)

1. Install ShellCheck via `apt`.
2. Discover all `*.sh` files under `bootstrap/scripts/` plus `local_ci.sh`.
3. Run `shellcheck --severity=warning` across all scripts in one invocation.

### Helm/Pluto (`helm-validate.yml` → `reusable-manifest-validation.yml`)

1. Checkout repository.
2. Install `helmfile` via `helmfile/helmfile-action`.
3. Render all Helm releases from `helmfile.yaml` using `helmfile template > /tmp/all-rendered.yaml`.
4. Render every chart deployed by an ArgoCD Application in `cluster/argocd/addons/` with
   `ruby ci/render-argocd-apps.rb /tmp/argocd-rendered.yaml` — same chart, version, release name,
   namespace, and Git value files ArgoCD uses (HTTP and OCI repos). Isolated Helm repo config, so
   local `helm repo` state can't affect it.
5. For `kubeconform` job:
	 - Install tools using `yokawasa/action-setup-kube-tools`.
	 - Validate raw manifests under `cluster/` and `workloads/` (excluding `values.yaml` and `patches/`).
	 - Validate both rendered files in strict mode.
	 - Run `ruby ci/policy-check.rb` over raw + rendered manifests (rules below).
6. For `pluto` job:
	 - Install Pluto using `FairwindsOps/pluto/github-action@master`.
	 - Check raw manifests (`cluster/`, `workloads/`) and both rendered files for deprecated/removed APIs.

### Policy checks (`ci/policy-check.rb`)

Repo rules that schema validation can't express. Each violation prints one line; any violation
fails the job.

| Rule | Fails when | Why |
|---|---|---|
| `scrape-port` | A Service or pod template has `prometheus.io/scrape: "true"` but no `prometheus.io/port` | VictoriaMetrics' scrape jobs `keep_if_equal` on that annotation, so the target is silently dropped |
| `memory-limit` | A Deployment/StatefulSet/DaemonSet container has no `resources.limits.memory` (`replicas: 0` skipped) | An unbounded pod can OOM the controller or a Pi Zero |
| `vm-scrape-reload` | A container runs with `-promscrape.config` but no `-promscrape.configCheckInterval` | The VictoriaMetrics chart doesn't restart the pod on scrape-config changes, so edits never load |

Exceptions live in `EXCEPTIONS` at the top of the script, each keyed `rule:Kind/name/container`
with a reason. There are none today: the first run flagged MetalLB's three FRR sidecars, and the
fix was to disable FRR (`speaker.frr.enabled: false`, unused in L2 mode) rather than except them.

Not catchable statically: a scrape target whose labels clash with the target's own
(`exported_*` renames) — that depends on the data, so check it after deploy.

## Trigger Conditions

`shellcheck.yml` runs on:

- `pull_request` to `main` when files change in:
	- `bootstrap/scripts/**`
	- `local_ci.sh`
	- `.github/workflows/shellcheck.yml`
- `push` to `main`
- `workflow_dispatch` for manual runs

`helm-validate.yml` runs on:

- `pull_request` to `main` when files change in:
	- `cluster/**`
	- `workloads/**`
	- `helmfile.yaml`
	- `.github/workflows/helm-validate.yml`
	- `.github/workflows/reusable-manifest-validation.yml`
- `push` to `main`
- `workflow_dispatch` for manual runs

Also triggers on changes under `ci/**` (the render and policy scripts).

## Version Pinning

- Prefer major-version pins for GitHub Actions where available.
- Some actions may require full tag pins when a major alias is not published.

## Why This Exists

- Catch rendering and schema regressions early.
- Detect Kubernetes API deprecations before cluster upgrades.
- Keep CI portable as new Helm releases are added by updating `helmfile.yaml` only.
- Catch shell scripting bugs (bad redirects, unquoted expansions) before scripts run on hardware.
