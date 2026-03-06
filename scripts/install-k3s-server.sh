#!/usr/bin/env bash
# install-k3s-server.sh
# Run on the Raspberry Pi 4 controller to install K3s as the cluster control plane.

set -euo pipefail

echo "==> Installing K3s server on Pi 4 controller..."

curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode 644 \
  --disable traefik

echo ""
echo "==> Waiting for K3s to be ready..."
until kubectl get nodes &>/dev/null; do sleep 2; done

echo ""
echo "==> Cluster nodes:"
kubectl get nodes -o wide

echo ""
echo "==> Node token (needed for worker nodes):"
sudo cat /var/lib/rancher/k3s/server/node-token

echo ""
echo "Done. Save the token above and run install-k3s-agent.sh on each Pi Zero (p1-p4)."
