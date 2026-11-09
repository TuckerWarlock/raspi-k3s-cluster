# CLAUDE.md

GitOps repo for a K3s cluster: a Raspberry Pi 4 controller (`pi4controller`, 4GB) plus four
Pi Zero 2 W workers (`p1`–`p4`, 512MB each) on a ClusterHAT v2.5. ArgoCD deploys everything
from `main`, so **merging to `main` deploys to the live cluster**.

## Current state

- **Running:** K3s v1.37, MetalLB, Traefik (chart 42.x), ArgoCD v3.6 (chart 10.x),
  VictoriaMetrics single-node, vmalert + Alertmanager, kube-state-metrics, Gatus, ntfy
  (alerts from Gatus and Alertmanager land on the `cluster-status` topic).
- **Planned (on hold):** Tailscale subnet router + split DNS for `home.arpa`; VictoriaLogs
  (`victoria-logs-single` + `victoria-logs-collector`).
- **Removed:** Longhorn (too heavy; using K3s local-path), Prometheus/Grafana/Loki (replaced by
  VictoriaMetrics), Monday/Ollama (LLM inference too slow on the Pi 4 CPU).

## Repo layout

```
bootstrap/scripts/   # Run by hand on the Pis (setup-*, install-*, set-static-ip, uninstall)
bootstrap/docs/      # rebuild.md = the ordered runbook; 01–07 = reference + troubleshooting
cluster/argocd/      # argocd-values.yaml, root-application.yaml, addons/, config/, workloads/
cluster/core-system/ # MetalLB and Traefik Helm values (+ MetalLB IP pool config)
cluster/monitoring/  # VictoriaMetrics, vmalert, and kube-state-metrics values
workloads/<app>/     # App manifests + kustomization.yaml (e.g. gatus/)
helmfile.yaml        # Installs ArgoCD only — ArgoCD deploys everything else
local_ci.sh          # Same checks as CI
```

## Validate before every commit

```bash
./local_ci.sh   # shellcheck; render helmfile + ArgoCD-deployed charts; kubeconform, policy checks, Pluto
```

YAML syntax (Ruby's parser, built into macOS):

```bash
git ls-files '*.yaml' '*.yml' | ruby -ryaml -e 'STDIN.read.split("\n").each { |f| YAML.load_stream(File.read(f)) { } }' && echo "YAML OK"
```

Embedded YAML (e.g. the Gatus `config.yaml` inside `workloads/gatus/configmap.yaml`) is a
string to the outer parser — parse it separately when you change it.

CI renders `helmfile.yaml` (ArgoCD) **and** every chart an ArgoCD Application deploys
(`ci/render-argocd-apps.rb`), then runs kubeconform, Pluto, and `ci/policy-check.rb` on the
output. The policy rules (scrape annotations need a port, every container has a memory
limit, VictoriaMetrics reloads its scrape config) are in `.github/workflows/README.md`; add an
exception there only with a reason. A new Application field the render script doesn't know
(e.g. inline `helm.values`) makes it fail loudly — extend the script rather than work around it.

## Deploying changes

- **One new app per push.** ArgoCD syncs everything at once, and a simultaneous start of
  several pods is what OOM-killed the controller and corrupted its SD card. Check
  `kubectl top nodes` between pushes; stop if the controller is above 80% memory
  ([memory-management.md](bootstrap/docs/memory-management.md)).
- **New workload:** manifests in `workloads/<app>/`, an Application in
  `cluster/argocd/workloads/<app>.yaml` (copy `gatus.yaml`), and the filename in that folder's
  `kustomization.yaml`. Full steps: [07-argocd.md → Adding a workload](bootstrap/docs/07-argocd.md#adding-a-workload).
- ArgoCD polls Git every 5 minutes. To pull a change in now:
  `kubectl -n argocd annotate app <app> argocd.argoproj.io/refresh=normal --overwrite`.
- `kubectl` from the laptop reaches the cluster (`https://192.168.1.135:6443`).

## Helm values workflow

Helm silently ignores unknown keys, so wrong key names leave the cluster on chart defaults
with no error. Before creating or editing any `values.yaml`:

1. Find the chart source (the Application's `repoURL`, or `install-helm.sh`).
2. Get the upstream values for the pinned version: `helm show values <repo>/<chart> --version <v>`.
   Chart 42+ of Traefik also has a `values.schema.json` that fails rendering on unknown keys.
3. Confirm the exact key path for every setting, then write the values file with comments on
   anything non-obvious.
4. Render it (`helm template … -f values.yaml`) and check the output contains what you set.

Always pin chart versions (`targetRevision` in Applications, `version:` in `helmfile.yaml`).
K3s installs the latest stable release on every rebuild, so check chart compatibility with
the cluster's Kubernetes version when bumping — see the version-skew entries in
[07-argocd.md → Troubleshooting](bootstrap/docs/07-argocd.md#troubleshooting).

## Placement and constraints

- **pi4controller:** control plane plus anything that needs the LAN or a USB-backed PVC —
  MetalLB, Traefik, the ArgoCD application-controller, VictoriaMetrics, Gatus
  (`nodeSelector: kubernetes.io/hostname: pi4controller`).
- **p1–p4:** labelled `node-role.kubernetes.io/worker=worker` and `hardware=pi-zero-2w`.
  ArgoCD server, redis, and repo-server run here. Keep workloads small.
- **Don't taint the Pi Zeros** — the ArgoCD pods there have no toleration.
- **VictoriaMetrics** sits close to its 256Mi limit by design. Keep it lean: drop unused series at
  ingest (`server.relabel` in its values) rather than raising the limit, and never run whole-database
  queries against it (e.g. `count({__name__=~".+"})`) — one OOM-killed it.
- **Storage:** `local-path`. On the controller, PVCs go to the USB drive
  (`/mnt/usb/local-path-storage`), which also holds the containerd images and nightly K3s
  backups (`/mnt/usb/backups/`).

| Network | Value |
|---|---|
| Controller LAN (`eth0`) | `192.168.1.135` (static) |
| Pi-hole (separate device) | `192.168.1.158` |
| MetalLB pool / Traefik | `192.168.1.241`–`.254` / `.241` (router DHCP is `.2`–`.240`) |
| CNAT | `172.19.181.0/24` — controller `.254` on `br0`, p1–p4 `.1`–`.4` on `usb0` |
| Pods / Services | `10.42.0.0/16` / `10.43.0.0/16` (K3s defaults) |

Hostnames (→ `192.168.1.241`): `argocd`, `vm`, `status`, `traefik` `.cluster.local`, plus
`ntfy.home.arpa` — iOS won't resolve `.local` via DNS, so anything the phone uses needs a
non-`.local` name and its own mkcert cert.

## Shell scripts

`#!/usr/bin/env bash` + `set -euo pipefail`; output sections prefixed `==> `; quoted heredocs
(`<< 'EOF'`); must pass `shellcheck --severity=warning`. Keep each script's usage comment
header accurate.

| Script | Run as | Notes |
|--------|--------|-------|
| `setup-controller.sh` | user | Uses sudo internally; idempotent; installs fan service + backup timer |
| `set-static-ip.sh` | `sudo bash` | `sudo bash set-static-ip.sh 192.168.1.135` |
| `install-k3s-server.sh` | `sudo bash` | Needs cgroup flags in `cmdline.txt` |
| `install-k3s-agent.sh` | user | `K3S_TOKEN` + `NODE_IP` env vars; download first, never `curl \| bash` |
| `install-helm.sh` | user | Helm repos are per-user — sudo breaks them |

## Documentation rules

Update docs in the same commit as the change:

| Change | Update |
|---|---|
| A build or rebuild step | `bootstrap/docs/rebuild.md` — the **only** place ordered steps live; `01`–`07` link to it instead of repeating commands |
| Manifest or new directory | `README.md` repo tree; the relevant `bootstrap/docs/` reference guide |
| Helm values | Comments in the values file; the component's reference guide |
| Workflow | Top-of-file comment in the workflow; `.github/workflows/README.md` |
| Bootstrap script | Its usage header; `bootstrap/scripts/README.md`; `rebuild.md` if the step changes |
| `local_ci.sh` | Its top-of-file comment block |
| New tool | **Tools Used** in `README.md` |
| Architecture / network | `bootstrap/docs/architecture.md` (incl. the decisions log) |

Where operational details live (link, don't copy):

| Topic | Doc |
|---|---|
| Build/rebuild steps, kubeconfig, token swap, USB mount, restore | [rebuild.md](bootstrap/docs/rebuild.md) |
| ClusterHAT power rules, fan, CNAT | [01-clusterhat-setup.md](bootstrap/docs/01-clusterhat-setup.md) |
| K3s server flags, eviction | [02-k3s-server.md](bootstrap/docs/02-k3s-server.md), [memory-management.md](bootstrap/docs/memory-management.md) |
| Pi Zero underclocking, agent flags, labels | [03-k3s-agents.md](bootstrap/docs/03-k3s-agents.md) |
| ArgoCD layout and troubleshooting | [07-argocd.md](bootstrap/docs/07-argocd.md) |

## Commits

Conventional commits: `docs(...)`, `ci: ...`, `fix(...)`, `feat(...)`. Keep app additions in
their own commit so they can be pushed one at a time.

## Hard rules

- `/boot/firmware/cmdline.txt` must stay a **single line** — a second line stops the Pi booting.
- Always `clusterctrl off` before rebooting or unplugging the Pi 4.
- Never commit secrets. Today's secrets — `cluster-local-tls`, `ntfy-tls`, `gatus-ntfy`,
  `alertmanager-ntfy` — and
  ntfy's users/tokens are created by hand ([rebuild.md 3.5](bootstrap/docs/rebuild.md#35--create-the-tls-secret-for-clusterlocal),
  [3.8](bootstrap/docs/rebuild.md#38--set-up-ntfy-certificate-users-gatus-token-iphone),
  [3.9](bootstrap/docs/rebuild.md#39--give-alertmanager-an-ntfy-token)).
