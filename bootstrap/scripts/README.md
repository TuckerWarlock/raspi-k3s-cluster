# Bootstrap Scripts

One-time setup scripts for provisioning the K3s cluster on Raspberry Pi hardware.

## Quick Reference

| Script | Purpose | Run As |
|--------|---------|--------|
| `setup-controller.sh` | CLI tools, swap, sysctls, shutdown hook, fan service, nightly K3s backup timer, Tailscale install, Pi Zero watchdog (disabled until step 3.11), weekly system file check | `bash` |
| `set-static-ip.sh` | Set static IPv4 on Pi 4 | `sudo bash` |
| `setup-agents.sh` | Persistent journal (32M cap) + CLI tools on Pi Zero workers | `bash` |
| `system-file-check.sh` | Weekly read-only SD-card integrity check: dpkg database, package checksums, ext4 errors (installed and enabled by `setup-controller.sh`) | systemd |
| `zero-watchdog.sh` | Power-cycles a Pi Zero that stops answering ping (installed by `setup-controller.sh`, run by `zero-watchdog.timer`) | systemd |
| `install-k3s-server.sh` | Install K3s control plane on Pi 4 | `sudo bash` |
| `install-k3s-agent.sh` | Install K3s agent on Pi Zero workers | `bash` |
| `install-helm.sh` | Install Helm, Helmfile | `bash` |
| `uninstall-k3s.sh` | Tear down K3s (server or agent) | `bash` |

## Usage

[`bootstrap/docs/rebuild.md`](../docs/rebuild.md) runs these in order. The short version:

- **Controller**: `setup-controller.sh` → `set-static-ip.sh` → (mount USB) → `install-k3s-server.sh` → `install-helm.sh`
- **Agents**: `install-k3s-agent.sh` with `K3S_TOKEN` and `NODE_IP` (optionally `setup-agents.sh` first for shell tools)
- **Apps**: `helmfile sync` (installs ArgoCD; ArgoCD deploys everything else)

## Resetting

- **Full reset:** run `uninstall-k3s.sh` on each Pi Zero, then on the Pi 4, and follow
  [`rebuild.md`](../docs/rebuild.md) from Phase 1.
- **Re-bootstrap the apps only:** `helmfile sync` and
  `kubectl apply -f cluster/argocd/root-application.yaml` are idempotent — re-run rebuild
  steps 3.3–3.4.
