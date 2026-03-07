#!/usr/bin/env bash
# install-k3s-server.sh
# Run on the Raspberry Pi 4 controller to install K3s as the cluster control plane.

set -euo pipefail

# K3s requires memory cgroup support. On Raspberry Pi this must be enabled manually.
check_cgroups() {
  local cmdline="/boot/firmware/cmdline.txt"
  if ! grep -q "cgroup_memory=1" "$cmdline" || ! grep -q "cgroup_enable=memory" "$cmdline"; then
    echo "==> [WARN] Memory cgroup flags missing from $cmdline"
    echo "    Adding 'cgroup_memory=1 cgroup_enable=memory'..."
    sudo sed -i '1s/^/cgroup_memory=1 cgroup_enable=memory /' "$cmdline"
    echo ""
    echo "==> Reboot required for cgroup changes to take effect."
    echo "    Run: sudo reboot"
    echo "    Then re-run this script after the reboot."
    exit 0
  fi
  echo "==> Memory cgroups OK"
}

check_cgroups

echo ""
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
