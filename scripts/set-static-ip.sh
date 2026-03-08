#!/usr/bin/env bash
# set-static-ip.sh
# Sets a static IPv4 address on the Pi 4 controller via NetworkManager (nmcli).
# Auto-detects the active interface (eth0 or wlan0), or override with INTERFACE env var.
#
# Usage (requires sudo):
#   sudo bash set-static-ip.sh 192.168.1.x
#     or
#   sudo STATIC_IP=192.168.1.x bash set-static-ip.sh
#
# The IP address is required — check your router's DHCP lease table for the assigned address.
# Optional env overrides: GATEWAY, DNS, INTERFACE

set -euo pipefail

STATIC_IP="${STATIC_IP:-${1:-}}"
GATEWAY="${GATEWAY:-192.168.1.1}"
DNS="${DNS:-1.1.1.1,8.8.8.8}"
PREFIX="24"  # /24 = 255.255.255.0

if [[ -z "$STATIC_IP" ]]; then
  echo "Usage:   sudo STATIC_IP=192.168.1.x bash set-static-ip.sh"
  echo "     or: sudo bash set-static-ip.sh 192.168.1.x"
  echo ""
  echo "Check your router's DHCP lease table to find the assigned IP."
  exit 1
fi

# Auto-detect active interface — prefer eth0 over wlan0
if [[ -n "${INTERFACE:-}" ]]; then
  echo "==> Using specified interface: ${INTERFACE}"
elif nmcli -t -f DEVICE,STATE dev status | grep -q "^eth0:connected"; then
  INTERFACE="eth0"
  echo "==> Auto-detected active interface: eth0"
elif nmcli -t -f DEVICE,STATE dev status | grep -q "^wlan0:connected"; then
  INTERFACE="wlan0"
  echo "==> Auto-detected active interface: wlan0"
else
  echo "ERROR: No active network interface found (checked eth0 and wlan0)."
  echo "       Run: nmcli device status"
  exit 1
fi

echo "    IP:      ${STATIC_IP}/${PREFIX}"
echo "    Gateway: ${GATEWAY}"
echo "    DNS:     ${DNS}"
echo ""

# Get the active NetworkManager connection name on this interface
CONN_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep ":${INTERFACE}$" | cut -d: -f1)

if [[ -z "$CONN_NAME" ]]; then
  echo "ERROR: No active NetworkManager connection found on ${INTERFACE}."
  echo "       Run: nmcli device status"
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
