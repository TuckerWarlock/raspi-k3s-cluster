# raspi-k3s-cluster

[![Cluster Validation](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/helm-validate.yml/badge.svg)](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/helm-validate.yml)
[![Dependabot Updates](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/dependabot/dependabot-updates)
[![ShellCheck](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/shellcheck.yml)

K3s Kubernetes cluster running on a Raspberry Pi 4 controller with four Pi Zero 2 W worker nodes via a [ClusterHAT](https://clusterctrl.com/).

**Hardware:**
- **Controller:** Raspberry Pi 4 (4GB RAM, K3s control plane)
- **Workers:** 4× Raspberry Pi Zero 2 W (512MB RAM each, connected via ClusterHAT)

> **⚠️ Power Supply Required:** The Pi 4 requires **5V/3A via USB-C**. Use a **USB-C to USB-C cable** with a proper PD power brick to avoid brownouts under load.

## Quick Start

**Building or rebuilding the cluster?** Follow [`bootstrap/docs/rebuild.md`](bootstrap/docs/rebuild.md)
top to bottom — it's the single ordered runbook for a first build and for recovering after
a reflash.

Reference guides (the *why*, plus troubleshooting) in [bootstrap/docs/](bootstrap/docs/):

1. [ClusterHAT OS & power](bootstrap/docs/01-clusterhat-setup.md) — images, flashing, `clusterctrl`, power rules
2. [K3s server](bootstrap/docs/02-k3s-server.md) — control-plane flags and eviction settings
3. [K3s agents](bootstrap/docs/03-k3s-agents.md) — Pi Zero underclocking, agent flags, labels
4. [MetalLB](bootstrap/docs/04-metallb.md) — bare-metal load balancer
5. [Traefik](bootstrap/docs/05-traefik.md) — ingress, TLS, hostnames
6. [ArgoCD](bootstrap/docs/07-argocd.md) — GitOps layout, adding workloads, troubleshooting

Also: [architecture.md](bootstrap/docs/architecture.md) (hardware, network, placement, decisions)
and [memory-management.md](bootstrap/docs/memory-management.md) (memory budget, safe deploys).

## Scripts

See [bootstrap/scripts/README.md](bootstrap/scripts/README.md) for the script reference.

## Repo Structure

```
raspi-k3s-cluster/
├── bootstrap/                      # Run by hand on the Pis
│   ├── scripts/                    # setup-*, install-*, set-static-ip, uninstall, reset
│   └── docs/
│       ├── rebuild.md              # ★ Ordered build / rebuild runbook
│       ├── 01-clusterhat-setup.md  # ClusterHAT OS & power
│       ├── 02-k3s-server.md        # K3s server reference
│       ├── 03-k3s-agents.md        # K3s agent reference
│       ├── 04-metallb.md           # MetalLB reference
│       ├── 05-traefik.md           # Traefik reference
│       ├── 07-argocd.md            # ArgoCD reference
│       ├── architecture.md         # Hardware, network, placement, decisions
│       └── memory-management.md    # Memory budget & safe deploys
│
├── cluster/                        # Infrastructure (deployed by ArgoCD)
│   ├── argocd/
│   │   ├── argocd-values.yaml      # ArgoCD Helm values (installed by helmfile)
│   │   ├── root-application.yaml   # App of apps → addons/
│   │   ├── addons/                 # One Application per infra component
│   │   ├── config/                 # ArgoCD ingress + OCI repo secret
│   │   └── workloads/              # One Application per workload → workloads/
│   ├── core-system/
│   │   ├── metallb/                # values.yaml + config/ (IP pool, L2 advertisement)
│   │   └── traefik/                # values.yaml
│   └── monitoring/                 # namespace + victoria-metrics/, vmalert/, kube-state-metrics/ values
│
├── workloads/                      # Applications (deployed by ArgoCD)
│   ├── gatus/                      # Status page → status.cluster.local
│   └── ntfy/                       # Push notifications → ntfy.home.arpa
│
├── CLAUDE.md                       # Instructions for AI assistants (Copilot's file points here)
├── helmfile.yaml                   # Bootstraps ArgoCD only
└── local_ci.sh                     # Runs the same checks as CI
```

### Directory Purposes

| Directory | Purpose | Managed By |
|-----------|---------|-----------|
| **bootstrap/** | Setup scripts & docs | Manual — re-run on every rebuild ([rebuild.md](bootstrap/docs/rebuild.md)) |
| **cluster/** | Infrastructure-as-code for cluster | ArgoCD (auto-synced from Git) |
| **workloads/** | User applications & services | ArgoCD (auto-synced from Git) |

## Tools Used

### Core Infrastructure
- [K3s](https://k3s.io/) — lightweight Kubernetes
- [Helm](https://helm.sh/) — package manager
- [Helmfile](https://helmfile.readthedocs.io/) — Helm release definitions

### Cluster Components
- [MetalLB](https://metallb.universe.tf/) — bare-metal load balancer
- [Traefik](https://traefik.io/) — ingress controller
- [ArgoCD](https://argoproj.github.io/cd/) — GitOps continuous deployment
- [VictoriaMetrics](https://victoriametrics.com/) — metrics storage + scraping (Prometheus-compatible), plus vmalert + Alertmanager for alert rules
- [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) — Kubernetes object state (pod restarts, replicas, node conditions) for alerting
- [Gatus](https://gatus.io/) — uptime/status checks at `status.cluster.local`
- [ntfy](https://ntfy.sh/) — self-hosted push notifications at `ntfy.home.arpa`

### Validation & CI
- [kubeconform](https://github.com/yannh/kubeconform) — Kubernetes manifest schema validation
- [Pluto](https://pluto.docs.fairwinds.com/) — API deprecation detection

See [bootstrap/docs/architecture.md](bootstrap/docs/architecture.md) for the full tech stack, network layout, and design decisions.
