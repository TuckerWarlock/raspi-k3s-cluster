#!/usr/bin/env bash
# setup-controller.sh
# Run once on the Raspberry Pi 4 controller after first boot.
# Installs CLI tools, sets up .bash_profile, and installs oh-my-posh + FiraCode font.

set -euo pipefail

echo "==> Clearing apt lists and updating..."
sudo rm -rf /var/lib/apt/lists/*
sudo apt update

echo ""
echo "==> Installing packages..."
sudo apt install -y lsd git curl

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
echo "==> Done! Run 'source ~/.bash_profile' or open a new shell to apply changes."
echo "    Make sure your terminal is set to use 'FiraCode Nerd Font Mono' for oh-my-posh to render correctly."
echo "    clusterctrl-off.service will automatically power off Pi Zero nodes on reboot/shutdown."
