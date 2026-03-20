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
