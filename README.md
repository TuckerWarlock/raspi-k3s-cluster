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

Complete setup guides are in [bootstrap/docs/](bootstrap/docs/):

1. [ClusterHAT OS & CNAT setup](bootstrap/docs/01-clusterhat-setup.md) — image selection, flashing, first boot
2. [K3s server on Pi 4](bootstrap/docs/02-k3s-server.md) — control plane setup
3. [K3s agents on Pi Zeros](bootstrap/docs/03-k3s-agents.md) — worker setup
4. [MetalLB load balancer](bootstrap/docs/04-metallb-load-balancer.md)
5. [Traefik ingress controller](bootstrap/docs/05-traefik-ingress.md)
6. [Longhorn distributed storage](bootstrap/docs/06-longhorn-storage.md)
7. [Prometheus monitoring](bootstrap/docs/08-prometheus-grafana-monitoring.md)
8. ArgoCD GitOps — deployed via `helmfile sync`

> **Rebuilding after a reflash?** → [`bootstrap/docs/post-reflash.md`](bootstrap/docs/post-reflash.md)

## Scripts

See [bootstrap/scripts/README.md](bootstrap/scripts/README.md) for the script reference.

## Repo Structure

```
raspi-k3s-cluster/
├── bootstrap/                           # One-time setup (manual, hands-off after)
│   ├── scripts/                         # Installation scripts
│   │   ├── README.md                   # Script reference
│   │   ├── install-helm.sh             # Helm, Helmfile, open-iscsi
│   │   ├── install-k3s-agent.sh        # K3s agent on workers
│   │   ├── install-k3s-server.sh       # K3s control plane
│   │   ├── set-static-ip.sh            # Static IP setup
│   │   ├── setup-agents.sh             # Pi Zero agent setup
│   │   ├── setup-controller.sh         # Pi 4 controller setup
│   │   ├── cleanup-longhorn.sh         # Longhorn cleanup utility
│   │   └── uninstall-k3s.sh            # K3s teardown
│   └── docs/                            # Setup guides & architecture
│       ├── 01-clusterhat-setup.md      # ClusterHAT hardware & OS
│       ├── 02-k3s-server.md            # K3s control plane setup
│       ├── 03-k3s-agents.md            # K3s worker setup
│       ├── 04-metallb-load-balancer.md # MetalLB load balancer
│       ├── 05-traefik-ingress.md       # Traefik ingress controller
│       ├── 06-longhorn-storage.md      # Longhorn distributed storage
│       ├── 08-prometheus-grafana-monitoring.md # Monitoring stack
│       └── architecture.md             # Architecture & decisions
│
├── cluster/                             # Kubernetes manifests (managed by ArgoCD)
│   ├── core-system/                    # Core infrastructure (via helmfile)
│   │   ├── metallb/                    # Load balancer
│   │   │   ├── ipaddresspool.yaml      # IP pool
│   │   │   ├── l2advertisement.yaml    # L2 advertisement
│   │   │   └── values.yaml             # Helm values
│   │   ├── traefik/                    # Ingress controller
│   │   │   ├── values.yaml             # Helm values
│   │   │   └── traefik-test-ingress.yaml # Test ingress
│   │   └── longhorn/                   # Distributed storage
│   │       ├── values.yaml             # Helm values
│   │       └── test-pvc.yaml           # Test PVC
│   ├── monitoring/                     # Monitoring (Prometheus via Kustomize)
│   │   ├── namespace.yaml
│   │   └── prometheus/                 # Prometheus StatefulSet + config
│   └── argocd/                         # GitOps management (via helmfile)
│       ├── namespace.yaml
│       ├── application-cluster.yaml
│       ├── ingress.yaml
│       └── values.yaml
│
├── workloads/                          # User applications (managed by ArgoCD)
│   └── (future applications)
│
├── helmfile.yaml                       # Helm release definitions
├── local_ci.sh                         # Local manifest validation
├── README.md                           # This file
└── .gitignore
```

### Directory Purposes

| Directory | Purpose | Managed By |
|-----------|---------|-----------|
| **bootstrap/** | One-time setup scripts & docs | Manual (don't run after setup) |
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
- [Longhorn](https://longhorn.io/) — distributed block storage
- [ArgoCD](https://argoproj.github.io/cd/) — GitOps continuous deployment
- [Prometheus](https://prometheus.io/) — metrics collection

### Validation & CI
- [kubeconform](https://github.com/yannh/kubeconform) — Kubernetes manifest schema validation
- [Pluto](https://pluto.docs.fairwinds.com/) — API deprecation detection

See [bootstrap/docs/architecture.md](bootstrap/docs/architecture.md) for the full tech stack, network layout, and design decisions.
