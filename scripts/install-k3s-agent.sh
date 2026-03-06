#!/usr/bin/env bash
# install-k3s-agent.sh
# Run on each Pi Zero 2 W worker node (p1–p4) to join the K3s cluster.
#
# Usage:
#   K3S_SERVER_IP=172.19.181.1 \
#   K3S_TOKEN=<token> \
#   NODE_IP=172.19.181.2 \
#   bash install-k3s-agent.sh

set -euo pipefail

K3S_SERVER_IP="${K3S_SERVER_IP:-172.19.181.1}"
K3S_TOKEN="${K3S_TOKEN:?'K3S_TOKEN is required. Get it from: sudo cat /var/lib/rancher/k3s/server/node-token on the Pi 4.'}"
NODE_IP="${NODE_IP:?'NODE_IP is required. Set to this node\'s CNAT IP, e.g. 172.19.181.2 for p1.'}"
FLANNEL_IFACE="${FLANNEL_IFACE:-usb0}"

echo "==> Installing K3s agent..."
echo "    Server:        https://${K3S_SERVER_IP}:6443"
echo "    This node IP:  ${NODE_IP}"
echo "    Interface:     ${FLANNEL_IFACE}"
echo ""

curl -sfL https://get.k3s.io | \
  K3S_URL="https://${K3S_SERVER_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN}" \
  sh -s - agent \
    --node-ip "${NODE_IP}" \
    --flannel-iface "${FLANNEL_IFACE}"

echo ""
echo "Done. Verify on the Pi 4 controller with: kubectl get nodes -o wide"
