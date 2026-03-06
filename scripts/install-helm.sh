#!/usr/bin/env bash
# install-helm.sh
# Run on the Raspberry Pi 4 controller to install Helm.

set -euo pipefail

echo "==> Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo ""
echo "==> Helm version:"
helm version

echo ""
echo "==> Adding common repos..."
helm repo add metallb https://metallb.github.io/metallb
helm repo add traefik https://traefik.github.io/charts
helm repo add longhorn https://charts.longhorn.io
helm repo update

echo ""
echo "Done. Run 'helm repo list' to verify."
