# raspi-k3s-cluster

[![Cluster Validation](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/helm-validate.yml/badge.svg)](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/helm-validate.yml)
[![Dependabot Updates](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/TuckerWarlock/raspi-k3s-cluster/actions/workflows/dependabot/dependabot-updates)

K3s Kubernetes cluster running on a Raspberry Pi 4 controller with four Pi Zero 2 W worker nodes via a [ClusterHAT](https://clusterctrl.com/).

## [Hardware](https://clusterctrl.com/setup-assembly)

| Role | Device | RAM |
|------|--------|-----|
| Controller (control plane) | Raspberry Pi 4 | 4-8GB (depends on model) |
| p1 — Worker | Raspberry Pi Zero 2 W (via ClusterHAT) | 512MB |
| p2 — Worker | Raspberry Pi Zero 2 W (via ClusterHAT) | 512MB |
| p3 — Worker | Raspberry Pi Zero 2 W (via ClusterHAT) | 512MB |
| p4 — Worker | Raspberry Pi Zero 2 W (via ClusterHAT) | 512MB |

Raspberry Pi can be purchased at these authorized resellers
- https://www.sparkfun.com/ - Raspberry Pi 4 board
- https://thepihut.com/ - ClusterHAT module and case (or you can 3d print a case)
- https://www.canakit.com/ - Raspberry Pi Zero 2W board

> **⚠️ Power Supply:** The Pi 4 requires **5V/3A via USB-C**. Use a **USB-C to USB-C cable** with a proper PD power brick — a USB-A to USB-C cable can under-deliver voltage (3.3V instead of 5V) even on a 2A brick, causing brownouts and random crashes under load.

## [ClusterHAT Images](https://clusterctrl.com/setup-software)

| Device | Image |
|--------|-------|
| (GUI) controller | CNAT - Desktop Controller - Desktop Bookworm image for the controller (3/3+/4/400) |
| (CLI) controller | CNAT - Lite Controller - Lite Bookworm image for the controller (3/3+/4/400)       |
| p1 | CNAT - Lite Bookworm — Zero 2/A3+/CM3/CM4 only — P1 |
| p2 | CNAT - Lite Bookworm — Zero 2/A3+/CM3/CM4 only — P2 |
| p3 | CNAT - Lite Bookworm — Zero 2/A3+/CM3/CM4 only — P3 |
| p4 | CNAT - Lite Bookworm — Zero 2/A3+/CM3/CM4 only — P4 |

> Each node image is unique — flash the correct P1/P2/P3/P4 image to each Pi Zero SD card.

All image releases can be downloaded from source here: https://dist1.8086.net/clusterctrl/bookworm/

## Scripts

See [bootstrap/scripts/README.md](bootstrap/scripts/README.md) for the script reference.

## Repo Structure

```
raspi-k3s-cluster/
├── bootstrap/                           # One-time setup (manual, hands-off after)
│   ├── scripts/                         # Installation scripts
│   │   ├── README.md                   # Script reference
│   │   ├── install-helm.sh             # Helm & Helmfile installation
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
│   ├── monitoring/                     # Monitoring (via kubectl apply)
│   │   ├── namespace.yaml
│   │   ├── prometheus-config.yaml
│   │   ├── prometheus-rbac.yaml
│   │   ├── prometheus-statefulset.yaml
│   │   ├── grafana.yaml
│   │   └── ingress.yaml
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

### Directory Purposes

| Directory | Purpose | Managed By |
|-----------|---------|-----------|
| **bootstrap/** | One-time setup scripts & docs | Manual (don't run after setup) |
| **cluster/** | Infrastructure-as-code for cluster | ArgoCD (auto-synced from Git) |
| **workloads/** | User applications & services | ArgoCD (auto-synced from Git) |
| **config/** | Kubeconfig, templates, examples | Manual |


## Tools Used

### Core Infrastructure
- [K3s](https://k3s.io/) — lightweight Kubernetes
- [Helm](https://helm.sh/) — package manager

### Cluster Components
- [MetalLB](https://metallb.universe.tf/) — bare-metal load balancer
- [Traefik](https://traefik.io/) — ingress controller (installed via Helm)
- [Longhorn](https://longhorn.io/) — distributed block storage
- [ArgoCD](https://argoproj.github.io/cd/) — GitOps continuous deployment

### CI / Validation
- [Helmfile](https://helmfile.readthedocs.io/) — declarative Helm release manager; drives chart rendering in CI
- [kubeconform](https://github.com/yannh/kubeconform) — Kubernetes manifest schema validation
- [Pluto](https://pluto.docs.fairwinds.com/) — Kubernetes API deprecation detection

### Administration & Monitoring
- [k9s](https://k9scli.io/) — terminal cluster UI
- [kubectl](https://kubernetes.io/docs/reference/kubectl/) — Kubernetes CLI

See [architecture.md](bootstrap/docs/architecture.md) for the full tech stack, network layout, workload placement strategy, and decisions log.

## Setup Order

Follow these guides in order to set up your cluster:

1. [ClusterHAT OS & CNAT setup](bootstrap/docs/01-clusterhat-setup.md)
2. [K3s server on Pi 4](bootstrap/docs/02-k3s-server.md)
3. [K3s agents on Pi Zeros](bootstrap/docs/03-k3s-agents.md)
4. [MetalLB load balancer](bootstrap/docs/04-metallb-load-balancer.md)
5. [Traefik ingress controller](bootstrap/docs/05-traefik-ingress.md)
6. [Longhorn distributed storage](bootstrap/docs/06-longhorn-storage.md)
7. [Prometheus + Grafana monitoring](bootstrap/docs/08-prometheus-grafana-monitoring.md)
8. ArgoCD (GitOps) — run: `bash bootstrap/scripts/install-argocd.sh`
