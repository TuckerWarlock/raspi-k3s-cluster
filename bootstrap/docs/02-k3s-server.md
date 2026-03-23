# 02 — K3s Server (Pi 4 Control Plane)

## Prerequisites

Before installing K3s, cgroup memory must be enabled or the service will fail to start.

```bash
sudo nano /boot/firmware/cmdline.txt
```

Append to the **end of the existing single line** (no new line):
```
cgroup_memory=1 cgroup_enable=memory
```

> **⚠️ cmdline.txt must remain a single line.** Do not press Enter or add any newlines.
> A second line or trailing newline will prevent the Pi from booting.
> Verify with `cat /boot/firmware/cmdline.txt | wc -l` — should output `1`.

Reboot, then SSH back in before continuing:
```bash
sudo reboot
```

## Install

```bash
cd ~/raspi-k3s-cluster
sudo bash bootstrap/scripts/install-k3s-server.sh
```

This script installs K3s with:
- `--write-kubeconfig-mode 644` — kubeconfig readable without sudo
- `--disable traefik` — install Traefik via Helm for full control
- `--disable servicelb` — **Required** if using MetalLB (conflicts with klipper)

## Verify

```bash
sudo systemctl status k3s
kubectl get nodes -o wide
```

Expected: `pi4controller` in `Ready` state.

## Retrieve Node Token

Workers need this token to join the cluster:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Save this — you'll need it for each Pi Zero agent install.

## kubeconfig (access from laptop)

K3s writes the kubeconfig to `/etc/rancher/k3s/k3s.yaml`. To use `kubectl` from your laptop:

```bash
scp warl0ck@pi4controller.local:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Replace 127.0.0.1 with the Pi 4's LAN IP
sed -i '' 's/127.0.0.1/192.168.1.10/g' ~/.kube/config  # macOS
# sed -i 's/127.0.0.1/192.168.1.10/g' ~/.kube/config   # Linux
```

> **⚠️ After each K3s reinstall, re-run the above commands.** The TLS certificates are regenerated on each install, and your kubeconfig will have a stale certificate. You'll see errors like `x509: certificate signed by unknown authority` if you don't refresh it.
