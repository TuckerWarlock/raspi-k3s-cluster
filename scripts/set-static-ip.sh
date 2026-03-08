#!/usr/bin/env bash
# set-static-ip.sh
# Sets a static IPv4 address on the Pi 4 controller via NetworkManager (nmcli).
# Run before install-k3s-server.sh to ensure a stable, predictable IP.
#
# Defaults:
#   STATIC_IP=192.168.1.4
#   GATEWAY=192.168.1.1
#   DNS=1.1.1.1,8.8.8.8
#   INTERFACE=wlan0

set -euo pipefail

STATIC_IP="${STATIC_IP:-192.168.1.4}"
GATEWAY="${GATEWAY:-192.168.1.1}"
DNS="${DNS:-1.1.1.1,8.8.8.8}"
INTERFACE="${INTERFACE:-wlan0}"
PREFIX="24"  # /24 = 255.255.255.0

echo "==> Setting static IP on ${INTERFACE}..."
echo "    IP:      ${STATIC_IP}/${PREFIX}"
echo "    Gateway: ${GATEWAY}"
echo "    DNS:     ${DNS}"
echo ""

# Get the active NetworkManager connection name on this interface
CONN_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep ":${INTERFACE}$" | cut -d: -f1)

if [[ -z "$CONN_NAME" ]]; then
  echo "ERROR: No active NetworkManager connection found on ${INTERFACE}."
  echo "       Is WiFi connected? Run: nmcli device status"
  exit 1
fi

echo "==> Active connection: '${CONN_NAME}'"

nmcli con mod "$CONN_NAME" \
  ipv4.addresses "${STATIC_IP}/${PREFIX}" \
  ipv4.gateway   "${GATEWAY}" \
  ipv4.dns       "${DNS}" \
  ipv4.method    manual

nmcli con up "$CONN_NAME"

echo ""
echo "==> Static IP set. Verifying..."
sleep 3
ip addr show "${INTERFACE}" | grep "inet "

echo ""
echo "Done. The controller is now reachable at ${STATIC_IP}"
echo "Update your ~/.ssh/known_hosts if you were previously connecting by a different IP."
