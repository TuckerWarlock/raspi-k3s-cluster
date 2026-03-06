# 03 — K3s Agents (Pi Zero 2 W Workers)

Run `scripts/install-k3s-agent.sh` on each Pi Zero, or follow manually.

## Prerequisites

- K3s server is running on the Pi 4
- You have the node token from `/var/lib/rancher/k3s/server/node-token`
- CNAT is enabled and the Pi Zeros can reach the Pi 4

## Install (run on each Pi Zero)

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://172.19.181.254:6443 \
  K3S_TOKEN=<node-token> \
  sh -s - agent \
    --node-ip <this-pizero-ip> \
    --flannel-iface usb0
```

Replace:
- `172.19.181.254` with your Pi 4's CNAT interface IP
- `<node-token>` with the token from the server
- `<this-pizero-ip>` with this node's IP (e.g. `172.19.181.1` for p1)
- `usb0` with the correct interface name if different (check with `ip link`)

## Verify (from Pi 4)

```bash
kubectl get nodes -o wide
```

All four Pi Zeros should appear with status `Ready` within ~60 seconds.

## Label Nodes

Good practice — label nodes by role or hardware:

```bash
kubectl label node p1 node-role.kubernetes.io/worker=worker
kubectl label node p1 hardware=pi-zero-2w
# Repeat for p2, p3, p4
```

## Resource Limits Note

Pi Zero 2 W has 512MB RAM. Avoid scheduling memory-hungry pods here.
Use node selectors or taints to keep control-plane workloads on the Pi 4:

```bash
# Taint Pi Zeros to only accept explicitly tolerating workloads
kubectl taint node p1 hardware=pi-zero-2w:NoSchedule
```
