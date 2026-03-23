# raspi-k3s-cluster

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

| Script | Purpose | Location |
|--------|---------|----------|
| `bootstrap/scripts/set-static-ip.sh` | Set static IPv4 on the Pi 4 via NetworkManager (pass IP as argument) |
| `bootstrap/scripts/setup-controller.sh` | Install CLI tools and configure Pi 4 controller |
| `bootstrap/scripts/setup-agents.sh` | Install CLI tools on Pi Zero workers |
| `bootstrap/scripts/install-k3s-server.sh` | Install K3s control plane on Pi 4 |
| `bootstrap/scripts/install-k3s-agent.sh` | Install K3s agent on Pi Zero workers |
| `bootstrap/scripts/install-helm.sh` | Install Helm on Pi 4 |
| `bootstrap/scripts/install-longhorn.sh` | Install Longhorn (distributed storage) |
| `bootstrap/scripts/install-argocd.sh` | Install ArgoCD (GitOps) |
| `bootstrap/scripts/cleanup-longhorn.sh` | Clean up and fully remove Longhorn |
| `bootstrap/scripts/uninstall-k3s.sh` | Tear down K3s (server or agent) |

## Setup Server - Pi 4 Controller

```bash
# 1. Edit cmdline.txt to enable cgroup memory (required for K3s)
sudo nano /boot/firmware/cmdline.txt
# Append to the END of the existing single line — do not add a newline:
cgroup_memory=1 cgroup_enable=memory

sudo reboot
# SSH back in after reboot, then continue:

# 2. (Optional) Set static IP — pass your desired IP as an argument
curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/set-static-ip.sh -o set-static-ip.sh
sudo bash set-static-ip.sh 192.168.1.10

# 3. Install CLI tools + .bash_profile (lsd, oh-my-posh, FiraCode)
curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/setup-controller.sh | bash

# 4. Install K3s
curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/install-k3s-server.sh | sudo bash

# 5. Install Helm
curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/install-helm.sh | bash
```

> After running `install-k3s-server.sh` on the controller, get the node token with:
```
sudo cat /var/lib/rancher/k3s/server/node-token
```


## Setup Agents - Pi Zero Workers (p1–p4)

```bash
# 1. Edit cmdline.txt to enable cgroup memory (required for K3s)
sudo nano /boot/firmware/cmdline.txt
# Append to the END of the existing single line — do not add a newline:
cgroup_memory=1 cgroup_enable=memory

sudo reboot
# SSH back in after reboot, then continue:

# 2. Install CLI tools + .bash_profile (lsd, oh-my-posh tokyo theme, FiraCode)
curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/setup-agents.sh | bash

# 3. Install K3s agent (pass in token and node IP)
curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/install-k3s-agent.sh -o install-k3s-agent.sh
K3S_TOKEN=abc123::server:def456 NODE_IP=172.19.181.x bash install-k3s-agent.sh
```

## Network Layout

The ClusterHAT uses CNAT to route the p1–p4 subnet through the Pi 4 controller.

```
LAN
 └── Raspberry Pi 4 controller (eth0: 192.168.1.x, usb0: 172.19.181.254)
      ├── p1 (Pi Zero 2 W)  172.19.181.1
      ├── p2 (Pi Zero 2 W)  172.19.181.2
      ├── p3 (Pi Zero 2 W)  172.19.181.3
      └── p4 (Pi Zero 2 W)  172.19.181.4
```

> Adjust IPs to match your actual CNAT subnet.

## Monitoring — k9s from Your Laptop

k9s gives you a full terminal UI for the cluster without SSH-ing into the Pi.

**1. Copy the kubeconfig to your laptop** (run this on your laptop):
```bash
mkdir -p ~/.kube
scp warl0ck@pi4controller.local:/etc/rancher/k3s/k3s.yaml ~/.kube/config
```

**2. Update the server address** (the default `127.0.0.1` only works on the Pi itself):
```bash
# macOS
sed -i '' 's/127.0.0.1/192.168.1.10/g' ~/.kube/config

# Linux
sed -i 's/127.0.0.1/192.168.1.10/g' ~/.kube/config
```
Replace `192.168.1.10` with your Pi 4 controller's actual static IP if different.

**3. Install k9s:**
```bash
# macOS
brew install k9s

# Linux
curl -sS https://webinstall.dev/k9s | bash
```

**4. Launch:**
```bash
k9s
```

> If the kubeconfig on the Pi is ever regenerated (e.g. after a K3s reinstall), re-run the `scp` command to pull the updated file.

## Repo Structure

```
raspi-k3s-cluster/
├── bootstrap/                           # One-time setup (manual, hands-off after)
│   ├── scripts/                         # Installation scripts
│   │   ├── install-argocd.sh           # ArgoCD (GitOps) setup
│   │   ├── install-helm.sh             # Helm installation
│   │   ├── install-k3s-agent.sh        # K3s agent on workers
│   │   ├── install-k3s-server.sh       # K3s control plane
│   │   ├── install-longhorn.sh         # Longhorn storage
│   │   ├── cleanup-longhorn.sh         # Longhorn cleanup utility
│   │   ├── set-static-ip.sh            # Static IP setup
│   │   ├── setup-agents.sh             # Pi Zero agent setup
│   │   ├── setup-controller.sh         # Pi 4 controller setup
│   │   └── uninstall-k3s.sh            # K3s teardown
│   └── docs/                            # Setup guides & architecture
│       ├── 01-clusterhat-setup.md      # ClusterHAT hardware & OS
│       ├── 01b-clusterctrl-reference.md # clusterctrl command reference
│       ├── 02-k3s-server.md            # K3s control plane setup
│       ├── 03-k3s-agents.md            # K3s worker setup
│       ├── 04-metallb.md               # Load balancer setup
│       ├── 05-ingress.md               # Traefik ingress setup
│       ├── 06-longhorn.md              # Longhorn storage setup
│       └── architecture.md             # Detailed architecture & decisions
│
├── cluster/                             # Kubernetes manifests (managed by ArgoCD)
│   ├── argocd/                         # ArgoCD configuration
│   │   ├── namespace.yaml              # argocd namespace
│   │   ├── application-cluster.yaml    # Cluster self-management Application
│   │   ├── ingress.yaml                # ArgoCD UI Ingress (Traefik)
│   │   └── values.yaml                 # Helm values reference
│   └── core-system/                    # Core cluster components
│       ├── metallb/                    # Load balancer
│       │   ├── ipaddresspool.yaml      # IP pool configuration
│       │   └── l2advertisement.yaml    # L2 advertisement
│       ├── traefik/                    # Ingress controller
│       │   ├── values.yaml             # Helm values
│       │   └── traefik-test-ingress.yaml
│       └── longhorn/                   # Distributed block storage
│           └── test-pvc.yaml           # Test PVC (for verification)
│
├── workloads/                          # User applications (managed by ArgoCD)
│   └── (future applications)
│
├── config/                             # Configuration & examples
│   └── (kubeconfig, templates, etc.)
│
├── .github/
│   ├── copilot-instructions.md         # Copilot CLI context
│   └── workflows/                      # CI/CD pipelines
│
├── README.md                           # This file
└── .gitignore
```

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
   - [clusterctrl command reference](bootstrap/docs/01b-clusterctrl-reference.md)
2. [K3s server on Pi 4](bootstrap/docs/02-k3s-server.md)
3. [K3s agents on Pi Zeros](bootstrap/docs/03-k3s-agents.md)
4. [MetalLB load balancer](bootstrap/docs/04-metallb.md)
5. [Ingress controller (Traefik)](bootstrap/docs/05-ingress.md)
6. [Storage with Longhorn](bootstrap/docs/06-longhorn.md)
7. ArgoCD (GitOps) — run: `bash bootstrap/scripts/install-argocd.sh`
