# raspi-k3s-cluster

K3s Kubernetes cluster running on a Raspberry Pi 4 controller with four Pi Zero 2 W worker nodes via a [ClusterHAT](https://clusterctrl.com/).

## [Hardware](https://clusterctrl.com/setup-assembly)

| Role | Device | RAM |
|------|--------|-----|
| Controller (control plane) | Raspberry Pi 4 | 4GB+ |
| p1 — Worker | Raspberry Pi Zero 2 W (via ClusterHAT) | 512MB |
| p2 — Worker | Raspberry Pi Zero 2 W (via ClusterHAT) | 512MB |
| p3 — Worker | Raspberry Pi Zero 2 W (via ClusterHAT) | 512MB |
| p4 — Worker | Raspberry Pi Zero 2 W (via ClusterHAT) | 512MB |

Raspberry Pi can be purchased at these authorized resellers
- https://www.sparkfun.com/ - Raspberry Pi 4
- https://thepihut.com/ - ClusterHAT and case (or you can 3d print a case)
- https://www.canakit.com/ - Raspberry Pi Zero 2W

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

## Network Layout

The ClusterHAT uses CNAT to route the p1–p4 subnet through the Pi 4 controller.

```
LAN
 └── Raspberry Pi 4 controller (eth0: 192.168.x.x, usb0: 172.19.181.254)
      ├── p1 (Pi Zero 2 W)  172.19.181.1
      ├── p2 (Pi Zero 2 W)  172.19.181.2
      ├── p3 (Pi Zero 2 W)  172.19.181.3
      └── p4 (Pi Zero 2 W)  172.19.181.4
```

> Adjust IPs to match your actual CNAT subnet.

## Architecture & Stack Decisions

See [docs/architecture.md](docs/architecture.md) for the full tech stack, network layout, workload placement strategy, and decisions log.

## Setup Order

1. [ClusterHAT OS & CNAT setup](docs/01-clusterhat-setup.md)
   - [clusterctrl command reference](docs/01b-clusterctrl-reference.md)
2. [K3s server on Pi 4](docs/02-k3s-server.md)
3. [K3s agents on Pi Zeros](docs/03-k3s-agents.md)
4. [MetalLB load balancer](docs/04-metallb.md)
5. [Ingress controller](docs/05-ingress.md)
6. [Storage with Longhorn](docs/06-longhorn.md)

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/install-k3s-server.sh` | Install K3s on the Pi 4 control plane |
| `scripts/install-k3s-agent.sh` | Install K3s agent on a Pi Zero worker |
| `scripts/install-helm.sh` | Install Helm on the Pi 4 |
| `scripts/uninstall-k3s.sh` | Tear down K3s (server or agent) |

## Tools Used

- [K3s](https://k3s.io/) — lightweight Kubernetes
- [Helm](https://helm.sh/) — package manager
- [k9s](https://k9scli.io/) — terminal cluster UI
- [MetalLB](https://metallb.universe.tf/) — bare-metal load balancer
- [Traefik](https://traefik.io/) — ingress (bundled with K3s)
- [Longhorn](https://longhorn.io/) — distributed block storage
