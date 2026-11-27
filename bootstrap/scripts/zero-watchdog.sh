#!/usr/bin/env bash
# zero-watchdog.sh
# Power-cycles a Pi Zero whose ClusterHAT port is on but which hasn't answered ping for
# FAIL_LIMIT consecutive runs, and gives up after MAX_CYCLES power-cycles that didn't bring it
# back. Installed to /usr/local/sbin by setup-controller.sh and run every minute by
# zero-watchdog.timer — which is NOT enabled until the Zeros are set up (rebuild.md step 3.11),
# so it can't power-cycle a node mid-install.
#
# Why: on 2026-11-27 p3's USB network link died at 05:18 while its OS kept running; it stayed
# NotReady for 3h18m until it was power-cycled by hand.
#
# Notifications go to the ntfy topic cluster-status if /etc/zero-watchdog.env sets NTFY_TOKEN
# (best effort — if the cluster is down too, the action is still logged to the journal:
# journalctl -t zero-watchdog).
#
# Env overrides (mainly for testing): FAIL_LIMIT, MAX_CYCLES, STATE_DIR, CLUSTERCTRL, ENV_FILE,
# NTFY_URL, NTFY_HOST.

set -euo pipefail

FAIL_LIMIT="${FAIL_LIMIT:-10}"            # minutes unreachable before a power-cycle
MAX_CYCLES="${MAX_CYCLES:-3}"             # power-cycles without recovery before giving up
STATE_DIR="${STATE_DIR:-/run/zero-watchdog}"   # tmpfs: counters reset when the Pi 4 reboots
CLUSTERCTRL="${CLUSTERCTRL:-/usr/sbin/clusterctrl}"
ENV_FILE="${ENV_FILE:-/etc/zero-watchdog.env}"
NTFY_URL="${NTFY_URL:-http://192.168.1.241/cluster-status}"   # Traefik; the Pi 4 can't resolve home.arpa
NTFY_HOST="${NTFY_HOST:-ntfy.home.arpa}"
NTFY_TOKEN=""

mkdir -p "$STATE_DIR"
if [[ -r "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

notify() {
  logger -t zero-watchdog "$1"
  [[ -n "$NTFY_TOKEN" ]] || return 0
  curl -fsS -m 10 -H "Host: $NTFY_HOST" -H "Authorization: Bearer $NTFY_TOKEN" \
    -H "Title: zero-watchdog" -H "Tags: warning" -d "$1" "$NTFY_URL" > /dev/null \
    || logger -t zero-watchdog "ntfy notification failed"
}

status="$("$CLUSTERCTRL" status)"

# With the USB hub off, every node is unreachable on purpose — don't cycle anything
if ! grep -qx 'hat_hub:1' <<< "$status"; then
  exit 0
fi

for i in 1 2 3 4; do
  node="p$i"
  fails_file="$STATE_DIR/$node.fails"
  cycles_file="$STATE_DIR/$node.cycles"

  # Port switched off on purpose: not ours to manage
  if ! grep -qx "$node:1" <<< "$status"; then
    rm -f "$fails_file" "$cycles_file"
    continue
  fi

  if ping -c1 -W2 "172.19.181.$i" > /dev/null 2>&1; then
    if [[ -f "$cycles_file" ]]; then
      notify "$node is reachable again after $(cat "$cycles_file") power-cycle(s)"
    fi
    rm -f "$fails_file" "$cycles_file"
    continue
  fi

  fails=$(( $(cat "$fails_file" 2> /dev/null || echo 0) + 1 ))
  echo "$fails" > "$fails_file"
  if (( fails < FAIL_LIMIT )); then
    continue
  fi

  cycles="$(cat "$cycles_file" 2> /dev/null || echo 0)"
  if (( cycles >= MAX_CYCLES )); then
    # Fires once: the fail counter keeps growing past FAIL_LIMIT until the node answers
    if (( fails == FAIL_LIMIT )); then
      notify "$node still unreachable after $cycles power-cycles — giving up, check it by hand"
    fi
    continue
  fi

  notify "$node unreachable for $fails min (port on) — power-cycling, attempt $(( cycles + 1 ))/$MAX_CYCLES"
  "$CLUSTERCTRL" off "$node"
  sleep 5
  "$CLUSTERCTRL" on "$node"
  echo $(( cycles + 1 )) > "$cycles_file"
  echo 0 > "$fails_file"
done
