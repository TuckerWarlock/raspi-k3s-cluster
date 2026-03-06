# 02 — K3s Server (Pi 4 Control Plane)

Run `scripts/install-k3s-server.sh` or follow steps below manually.

## Install

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode 644 \
  --disable traefik
```

> Traefik is disabled here so you can install a specific version via Helm later.
> Remove `--disable traefik` if you want K3s to manage it automatically.

## Verify

```bash
sudo systemctl status k3s
kubectl get nodes
```

## Retrieve Node Token

Workers need this token to join the cluster:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Save this value — you'll need it when running `install-k3s-agent.sh` on each Pi Zero.

## kubeconfig

K3s writes the kubeconfig to `/etc/rancher/k3s/k3s.yaml`.
The `--write-kubeconfig-mode 644` flag makes it readable without sudo.

To use kubectl from your laptop, copy and update the server IP:

```bash
scp pi@<pi4-ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Replace 127.0.0.1 with your Pi 4's LAN IP in the file
sed -i 's/127.0.0.1/<pi4-ip>/g' ~/.kube/config
```
