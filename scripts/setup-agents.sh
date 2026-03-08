#!/usr/bin/env bash
# setup-agents.sh
# Run on each Pi Zero 2 W worker node (p1–p4) after first boot.
# Installs CLI tools and sets up .bash_profile with oh-my-posh (tokyo theme).
#
# Usage:
#   bash setup-agents.sh
#   or
#   curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/setup-agents.sh | bash

set -euo pipefail

echo "==> Installing packages..."
sudo apt install -y lsd

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

# Aliases
alias ls='lsd'

# oh-my-posh
eval "$(oh-my-posh init bash --config ~/.cache/oh-my-posh/themes/tokyo.omp.json)"
EOF

echo ""
echo "==> Done! Run 'source ~/.bash_profile' or open a new shell to apply changes."
