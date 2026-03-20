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
> Verify with `cat /boot/firmware/cmdline.txt` — the entire file should be one line.

Reboot, then SSH back in before continuing:
```bash
sudo reboot
```

## Install

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb
```

> `--write-kubeconfig-mode 644` makes kubeconfig readable without sudo.
> `--disable traefik` — install Traefik via Helm for full control.
> `--disable servicelb` — disables the built-in klipper load balancer. **Required** if using MetalLB — they conflict and klipper will prevent MetalLB from setting up iptables DNAT rules.

If the service fails to start on the first run, start it manually after confirming cgroups are active:
```bash
sudo systemctl start k3s
```

## Fix kubeconfig permissions

If you installed without `--write-kubeconfig-mode 644`, fix it manually:
```bash
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
```

## Verify

```bash
sudo systemctl status k3s
kubectl get nodes -o wide
```

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

