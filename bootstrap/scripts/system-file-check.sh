#!/usr/bin/env bash
# system-file-check.sh
# Weekly read-only integrity check of the Pi 4's SD card, run by system-file-check.timer
# (installed and enabled by setup-controller.sh). Checks:
#   1. apt-get check   — the dpkg status database still parses
#   2. dpkg --verify   — installed package files still match their checksums (config files,
#                        which you're allowed to edit, are ignored)
#   3. dumpe2fs -h     — the root ext4 filesystem hasn't recorded errors
# Any failure pushes a notification to the ntfy topic cluster-status (if /etc/zero-watchdog.env
# sets NTFY_TOKEN — the watchdog's write-only token is reused) and exits 1, so the unit shows
# as failed in `systemctl --failed`. A clean run logs one line: journalctl -t system-file-check.
#
# Why: on 2026-11-27 the SD card silently corrupted /var/lib/dpkg/status, 13 package files, and
# directory entries in /lib — with no kernel errors, no reboot, and no undervoltage. It was only
# found because an apt run failed; this finds it within a week.
# Recovery steps: bootstrap/docs/rebuild.md → "Package files fail their checksums".
#
# Env overrides (mainly for testing): APT_GET, DPKG, DUMPE2FS, ROOT_DEV, ENV_FILE, NTFY_URL,
# NTFY_HOST, MAX_LISTED.

set -euo pipefail

APT_GET="${APT_GET:-apt-get}"
DPKG="${DPKG:-dpkg}"
DUMPE2FS="${DUMPE2FS:-dumpe2fs}"
ROOT_DEV="${ROOT_DEV:-$(findmnt -no SOURCE / 2> /dev/null || echo /dev/mmcblk0p2)}"
ENV_FILE="${ENV_FILE:-/etc/zero-watchdog.env}"
NTFY_URL="${NTFY_URL:-http://192.168.1.241/cluster-status}"   # Traefik; the Pi 4 can't resolve home.arpa
NTFY_HOST="${NTFY_HOST:-ntfy.home.arpa}"
MAX_LISTED="${MAX_LISTED:-5}"
NTFY_TOKEN=""

if [[ -r "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

notify() {
  logger -t system-file-check "$1"
  [[ -n "$NTFY_TOKEN" ]] || return 0
  curl -fsS -m 10 -H "Host: $NTFY_HOST" -H "Authorization: Bearer $NTFY_TOKEN" \
    -H "Title: system-file-check on $(hostname)" -H "Tags: rotating_light" -H "Priority: high" \
    -d "$1" "$NTFY_URL" > /dev/null \
    || logger -t system-file-check "ntfy notification failed"
}

problems=()

# 1. dpkg status database
if ! "$APT_GET" check > /dev/null 2>&1; then
  problems+=("apt-get check failed — /var/lib/dpkg/status may be corrupt")
fi

# 2. Package file checksums (only meaningful if the database parses). Lines look like
#    "??5??????   /usr/bin/screen" or "??5?????? c /etc/foo.conf"; skip the config files.
if (( ${#problems[@]} == 0 )); then
  bad_files="$("$DPKG" --verify 2> /dev/null | awk '$2 != "c" {print $NF}' || true)"
  if [[ -n "$bad_files" ]]; then
    count="$(wc -l <<< "$bad_files" | tr -d ' ')"
    listed="$(head -n "$MAX_LISTED" <<< "$bad_files" | paste -sd ' ' -)"
    problems+=("$count package file(s) fail their checksums: $listed")
  fi
fi

# 3. ext4 error counter on the root filesystem
fs_errors="$("$DUMPE2FS" -h "$ROOT_DEV" 2> /dev/null | awk -F: '/^FS Error count/ {gsub(/ /, "", $2); print $2}' || true)"
if [[ -n "$fs_errors" && "$fs_errors" != "0" ]]; then
  problems+=("$ROOT_DEV has recorded $fs_errors filesystem error(s)")
fi

if (( ${#problems[@]} == 0 )); then
  logger -t system-file-check "OK: dpkg database parses, package checksums match, no filesystem errors on $ROOT_DEV"
  exit 0
fi

notify "$(printf '%s\n' "${problems[@]}")
See rebuild.md → \"Package files fail their checksums\"."
exit 1
