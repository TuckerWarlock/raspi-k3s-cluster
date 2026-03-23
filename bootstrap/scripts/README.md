# Bootstrap Scripts

One-time setup scripts for provisioning the K3s cluster on Raspberry Pi hardware.

## Quick Reference

| Script | Purpose | Run As |
|--------|---------|--------|
| `set-static-ip.sh` | Set static IPv4 on Pi 4 | `sudo bash` |
| `setup-controller.sh` | Install CLI tools on Pi 4 controller | `bash` |
| `setup-agents.sh` | Install CLI tools on Pi Zero workers | `bash` |
| `install-k3s-server.sh` | Install K3s control plane on Pi 4 | `sudo bash` |
| `install-k3s-agent.sh` | Install K3s agent on Pi Zero workers | `bash` |
| `install-helm.sh` | Install Helm, Helmfile, open-iscsi | `bash` |
| `cleanup-longhorn.sh` | Remove Longhorn and backing storage | `bash` |
| `uninstall-k3s.sh` | Tear down K3s (server or agent) | `bash` |

## Usage

See the setup guides in [bootstrap/docs/](../docs/) for step-by-step instructions on when and how to run each script.

Key patterns:
- **Controller setup**: `setup-controller.sh` → `install-k3s-server.sh` → `install-helm.sh`
- **Agent setup**: `setup-agents.sh` → `install-k3s-agent.sh` (with K3S_TOKEN env var)
- **Core infrastructure**: `helmfile sync` (replaces old `install-longhorn.sh` and `install-argocd.sh`)
