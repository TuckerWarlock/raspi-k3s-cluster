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

echo ""
echo "==> Installing FiraCode Nerd Font..."
oh-my-posh font install firacode

echo ""
echo "==> Writing ~/.bash_profile..."
cat > "$HOME/.bash_profile" << 'EOF'
# PATH
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Aliases
alias ls='lsd'

# oh-my-posh
eval "$(oh-my-posh init bash --config ~/.cache/oh-my-posh/omp.cache/night-owl.omp.json)"
EOF

echo ""
echo "==> Done! Run 'source ~/.bash_profile' or open a new shell to apply changes."
echo "    Make sure your terminal is set to use 'FiraCode Nerd Font Mono' for oh-my-posh to render correctly."
