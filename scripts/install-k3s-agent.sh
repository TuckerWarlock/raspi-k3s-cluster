#!/usr/bin/env bash
# install-k3s-agent.sh
# Run on each Pi Zero 2 W worker node (p1–p4) to join the K3s cluster.
#
# Usage (interactive — will prompt for token and node IP):
#   bash install-k3s-agent.sh
#
# Usage (non-interactive — pass values as env vars):
#   K3S_TOKEN=<token> NODE_IP=172.19.181.1 bash install-k3s-agent.sh

set -euo pipefail

# K3s requires memory cgroup support. On Raspberry Pi this must be enabled manually.
# This function is idempotent — safe to run multiple times.
check_cgroups() {
  local cmdline="/boot/firmware/cmdline.txt"

  # Already set — nothing to do
  if grep -q "cgroup_memory=1" "$cmdline" && grep -q "cgroup_enable=memory" "$cmdline"; then
    echo "==> Memory cgroups OK"
    return
  fi

  echo "==> [WARN] Memory cgroup flags missing from $cmdline"
  echo "    Removing any partial flags and writing cleanly..."

  # Strip any partial/duplicate flags that may have been added by a previous run,
  # then append both flags to the end of the line (as recommended by K3s docs).
  sudo sed -i \
    's/ cgroup_memory=1//g;
     s/ cgroup_enable=memory//g;
     s/$/ cgroup_memory=1 cgroup_enable=memory/' \
    "$cmdline"

  echo ""
  echo "    Updated $cmdline:"
  cat "$cmdline"
  echo ""
  echo "==> Reboot required for cgroup changes to take effect."
  echo "    Run: sudo reboot"
  echo "    Then re-run this script after the reboot."
  exit 0
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
