#!/usr/bin/env bash
# install-k3s-server.sh
# Run on the Raspberry Pi 4 controller to install K3s as the cluster control plane.
#
# Prerequisites:
#   Before running this script, ensure cgroup memory is enabled in cmdline.txt:
#     sudo nano /boot/firmware/cmdline.txt
#   Append to the end of the existing line (do not add a new line):
#     cgroup_memory=1 cgroup_enable=memory
#   Then reboot: sudo reboot
#   Re-run this script after the reboot.

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
echo "==> Installing K3s server on Pi 4 controller..."
echo "    Memory management flags:"
echo "      system-reserved=512Mi  — keeps 512MB free for OS/kernel/systemd"
echo "      eviction-soft=512Mi    — gracefully evicts pods before hitting hard limit"
echo "      eviction-hard=300Mi    — force-evicts pods to prevent kernel OOM killer"

curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb \
  --kubelet-arg=system-reserved=cpu=250m,memory=512Mi \
  --kubelet-arg=eviction-hard=memory.available<300Mi,nodefs.available<10% \
  --kubelet-arg=eviction-soft=memory.available<512Mi,nodefs.available<15% \
  --kubelet-arg=eviction-soft-grace-period=memory.available=2m,nodefs.available=5m

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
