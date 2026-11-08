# Bootstrap Scripts

One-time setup scripts for provisioning the K3s cluster on Raspberry Pi hardware.

## Quick Reference

| Script | Purpose | Run As |
|--------|---------|--------|
| `setup-controller.sh` | CLI tools, swap, sysctls, shutdown hook, fan service, nightly K3s backup timer | `bash` |
| `set-static-ip.sh` | Set static IPv4 on Pi 4 | `sudo bash` |
| `setup-agents.sh` | Install CLI tools on Pi Zero workers | `bash` |
| `install-k3s-server.sh` | Install K3s control plane on Pi 4 | `sudo bash` |
| `install-k3s-agent.sh` | Install K3s agent on Pi Zero workers | `bash` |
| `install-helm.sh` | Install Helm, Helmfile | `bash` |
| `uninstall-k3s.sh` | Tear down K3s (server or agent) | `bash` |
| `reset-helm-releases.sh` | Uninstall Helm releases and clear Helm config (predates ArgoCD managing MetalLB/Traefik) | `bash` |

## Usage

[`bootstrap/docs/rebuild.md`](../docs/rebuild.md) runs these in order. The short version:

- **Controller**: `setup-controller.sh` → `set-static-ip.sh` → (mount USB) → `install-k3s-server.sh` → `install-helm.sh`
- **Agents**: `install-k3s-agent.sh` with `K3S_TOKEN` and `NODE_IP` (optionally `setup-agents.sh` first for shell tools)
- **Apps**: `helmfile sync` (installs ArgoCD; ArgoCD deploys everything else)
