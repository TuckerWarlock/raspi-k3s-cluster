#!/usr/bin/env bash
# setup-controller.sh
# Run once on the Raspberry Pi 4 controller after first boot (and after every reflash).
# Installs CLI tools, sets up .bash_profile, and installs oh-my-posh + FiraCode font; configures
# swap, memory sysctls, the ClusterHAT shutdown hook and fan service, the nightly K3s backup
# timer, installs Tailscale (subnet router — `tailscale up` is a manual step, see
# bootstrap/docs/rebuild.md step 3.10), installs the Pi Zero watchdog timer (left disabled
# until the Zeros are set up — rebuild.md step 3.11), and enables a weekly read-only SD-card
# integrity check (system-file-check.timer).

set -euo pipefail

echo "==> Clearing apt lists and updating..."
sudo rm -rf /var/lib/apt/lists/*
sudo apt update

echo ""
echo "==> Installing packages..."
sudo apt install -y lsd git curl sqlite3

echo ""
echo "==> Installing oh-my-posh..."
curl -s https://ohmyposh.dev/install.sh | bash -s

# Add ~/.local/bin to PATH for the remainder of this script
export PATH=$PATH:/home/warl0ck/.local/bin

echo ""
echo "==> Installing FiraCode Nerd Font..."
oh-my-posh font install firacode

echo ""
echo "==> Writing ~/.bash_profile..."
cat > "$HOME/.bash_profile" << 'EOF'
# PATH
export PATH=$PATH:/home/warl0ck/.local/bin

# Kubernetes
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Aliases
alias ls='lsd'
alias cc='clusterctrl'
alias k='kubectl'

# oh-my-posh
eval "$(oh-my-posh init bash --config ~/.cache/oh-my-posh/themes/night-owl.omp.json)"
EOF

echo ""
echo "==> Creating 1GB swap file..."
# Swap gives the kernel a safety valve — pods slow down instead of crashing the SD card.
# K3s kubelet eviction will still evict pods before swap fills, so this is a last resort.
if [ -f /swapfile ]; then
  echo "    /swapfile already exists, skipping"
else
  sudo fallocate -l 1G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  # Persist across reboots
  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  fi
  echo "    1GB swap created and enabled at /swapfile"
fi

echo ""
echo "==> Applying kernel memory tuning..."
sudo tee /etc/sysctl.d/99-k3s-memory.conf > /dev/null << 'EOF'
# Use swap only under real pressure — prefer RAM
vm.swappiness=10

# Be less aggressive about freeing page cache
vm.vfs_cache_pressure=50

# Kill the task that triggered OOM, not a random victim
vm.oom_kill_allocating_task=1

# Do not panic on OOM — let the OOM killer recover gracefully
vm.panic_on_oom=0
EOF
sudo sysctl --system > /dev/null
echo "    sysctl tuning applied (/etc/sysctl.d/99-k3s-memory.conf)"

echo ""
echo "==> Installing clusterctrl shutdown hook..."
sudo tee /etc/systemd/system/clusterctrl-off.service > /dev/null << 'EOF'
[Unit]
Description=Power off ClusterHAT nodes before shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
Requires=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/clusterctrl off
RemainAfterExit=yes
TimeoutStartSec=10

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF

sudo systemctl enable clusterctrl-off.service
echo "    clusterctrl-off.service enabled — nodes will auto power-off on reboot/shutdown."

echo ""
echo "==> Installing ClusterHAT fan service..."
# The case fan is on GPIO 18, which must be set as an output before `clusterctrl fan on`
# works. pinctrl replaces the deprecated raspi-gpio on Bookworm.
sudo tee /etc/systemd/system/clusterhat-fan.service > /dev/null << 'EOF'
[Unit]
Description=Enable ClusterHAT case fan (GPIO 18)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/pinctrl set 18 op pn dh
ExecStart=/usr/sbin/clusterctrl fan on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now clusterhat-fan.service
echo "    clusterhat-fan.service enabled — fan starts on every boot."

echo ""
echo "==> Installing nightly K3s state backup to the USB drive..."
# Power loss can corrupt the SD card. This copies the K3s datastore, token, and certs to
# the USB drive every night so a reflash can restore the cluster instead of rebuilding it.
# Restore steps: bootstrap/docs/rebuild.md (step 1.8).
sudo tee /usr/local/sbin/k3s-backup.sh > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
SRC=/var/lib/rancher/k3s/server
DEST=/mnt/usb/backups/k3s-$(date +%F)
mkdir -p "$DEST"
sqlite3 "$SRC/db/state.db" ".backup '$DEST/state.db'"
cp "$SRC/token" "$DEST/token"
tar -czf "$DEST/tls-cred.tar.gz" -C "$SRC" tls cred
# Keep the 7 most recent backups
ls -1d /mnt/usb/backups/k3s-* | head -n -7 | xargs -r rm -rf
EOF
sudo chmod 755 /usr/local/sbin/k3s-backup.sh

sudo tee /etc/systemd/system/k3s-backup.service > /dev/null << 'EOF'
[Unit]
Description=Back up K3s datastore, token, and certs to the USB drive
RequiresMountsFor=/mnt/usb
ConditionPathExists=/var/lib/rancher/k3s/server/db/state.db

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/k3s-backup.sh
EOF

sudo tee /etc/systemd/system/k3s-backup.timer > /dev/null << 'EOF'
[Unit]
Description=Nightly K3s state backup

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now k3s-backup.timer
echo "    k3s-backup.timer enabled — nightly backups to /mnt/usb/backups/"

echo ""
echo "==> Installing Tailscale (subnet router for remote access)..."
# Official Debian Bookworm repo. Runs on the host, not in Kubernetes, so remote access
# survives K3s being down. Login and route advertisement are manual: rebuild.md step 3.10.
if command -v tailscale > /dev/null 2>&1; then
  echo "    tailscale already installed, skipping"
else
  curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
    | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
  curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
    | sudo tee /etc/apt/sources.list.d/tailscale.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y tailscale
fi

# Subnet routers forward traffic for 192.168.1.0/24 (IPv4 forwarding is also needed by CNAT)
sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf > /dev/null
echo "    tailscale installed — next: sudo tailscale up (rebuild.md step 3.10)"

echo ""
echo "==> Installing Pi Zero watchdog (power-cycles a Zero that stops answering ping)..."
# Installed but NOT enabled: enabling it before the Zeros are flashed and joined would
# power-cycle them mid-install. Enable it in rebuild.md step 3.11.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo install -m 755 "$SCRIPT_DIR/zero-watchdog.sh" /usr/local/sbin/zero-watchdog.sh

sudo tee /etc/systemd/system/zero-watchdog.service > /dev/null << 'EOF'
[Unit]
Description=Power-cycle Pi Zero nodes that stopped answering ping
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/zero-watchdog.sh
EOF

sudo tee /etc/systemd/system/zero-watchdog.timer > /dev/null << 'EOF'
[Unit]
Description=Check Pi Zero nodes every minute

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
if systemctl is-enabled --quiet zero-watchdog.timer; then
  echo "    zero-watchdog.timer already enabled — script updated"
else
  echo "    zero-watchdog installed (disabled) — enable it in rebuild.md step 3.11"
fi

echo ""
echo "==> Installing weekly system file check (dpkg database, package checksums, ext4 errors)..."
# Read-only, so it's enabled right away. Notifications reuse the watchdog's ntfy token
# (/etc/zero-watchdog.env, rebuild.md step 3.11); without it, results only go to the journal.
sudo install -m 755 "$SCRIPT_DIR/system-file-check.sh" /usr/local/sbin/system-file-check.sh

sudo tee /etc/systemd/system/system-file-check.service > /dev/null << 'EOF'
[Unit]
Description=Check the SD card for silently corrupted system files

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/system-file-check.sh
# dpkg --verify reads every package file; stay out of the cluster's way
Nice=19
IOSchedulingClass=idle
EOF

sudo tee /etc/systemd/system/system-file-check.timer > /dev/null << 'EOF'
[Unit]
Description=Weekly SD-card integrity check

[Timer]
# Sunday 04:00, after the 03:00 K3s backup; Persistent runs a missed check after boot
OnCalendar=Sun *-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now system-file-check.timer
echo "    system-file-check.timer enabled — weekly; run now: sudo systemctl start system-file-check.service"

echo ""
echo "==> Done! Run 'source ~/.bash_profile' or open a new shell to apply changes."
echo "    Make sure your terminal is set to use 'FiraCode Nerd Font Mono' for oh-my-posh to render correctly."
echo "    clusterctrl-off.service will automatically power off Pi Zero nodes on reboot/shutdown."
