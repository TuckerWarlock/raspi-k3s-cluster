#!/usr/bin/env bash
# uninstall-k3s.sh
# Uninstalls K3s from the current node (works for both server and agent).

set -euo pipefail

if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
  echo "==> Uninstalling K3s server..."
  /usr/local/bin/k3s-uninstall.sh
elif [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
  echo "==> Uninstalling K3s agent..."
  /usr/local/bin/k3s-agent-uninstall.sh
else
  echo "No K3s installation found on this node."
  exit 1
fi

echo "Done."
