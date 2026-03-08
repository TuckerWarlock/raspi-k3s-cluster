#!/usr/bin/env bash
# install-k3s-agent.sh
# Run on each Pi Zero 2 W worker node (p1–p4) to join the K3s cluster.
#
# Prerequisites:
#   Before running this script, ensure cgroup memory is enabled in cmdline.txt:
#     sudo nano /boot/firmware/cmdline.txt
#   Append to the end of the existing line (do not add a new line):
#     cgroup_memory=1 cgroup_enable=memory
#   Then reboot: sudo reboot
#   Re-run this script after the reboot.
#
# Usage (interactive — will prompt for token and node IP):
#   bash install-k3s-agent.sh
#
# Usage (non-interactive — pass values as env vars):
#   K3S_TOKEN=<token> NODE_IP=172.19.181.1 bash install-k3s-agent.sh

set -euo pipefail

# Verify cgroup memory flags are present before attempting install.
check_cgroups() {
  local cmdline="/boot/firmware/cmdline.txt"
  if grep -q "cgroup_memory=1" "$cmdline" && grep -q "cgroup_enable=memory" "$cmdline"; then
    echo "==> Memory cgroups OK"
    return
  fi

  echo ""
  echo "==> [ERROR] Memory cgroup flags missing from $cmdline"
  echo ""
  echo "    Add the following to the END of the single line in $cmdline:"
  echo "      cgroup_memory=1 cgroup_enable=memory"
  echo ""
  echo "    Edit the file:"
  echo "      sudo nano $cmdline"
  echo ""
  echo "    Then reboot and re-run this script:"
  echo "      sudo reboot"
  echo ""
  exit 1
}

check_cgroups
echo ""

K3S_SERVER_IP="${K3S_SERVER_IP:-172.19.181.254}"
FLANNEL_IFACE="${FLANNEL_IFACE:-usb0}"

if [[ -z "${K3S_TOKEN:-}" ]]; then
  read -rp "Enter the K3s node token (from controller: sudo cat /var/lib/rancher/k3s/server/node-token): " K3S_TOKEN
fi

if [[ -z "${NODE_IP:-}" ]]; then
  read -rp "Enter this node's CNAT IP (p1=172.19.181.1, p2=172.19.181.2, p3=172.19.181.3, p4=172.19.181.4): " NODE_IP
fi

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
