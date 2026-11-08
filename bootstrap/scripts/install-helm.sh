#!/usr/bin/env bash
# install-helm.sh
# Run on the Raspberry Pi 4 controller to install Helm and Helmfile.
# Do NOT run with sudo — the Helm installer handles privilege escalation internally.
# Helm repos are added for the current user.
#
# Usage:
#   curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/install-helm.sh | bash
#     or
#   bash install-helm.sh

set -euo pipefail

echo "==> Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo ""
echo "==> Helm version:"
helm version

echo ""
echo "==> Installing Helmfile..."
# Keep in sync with HELMFILE_VERSION in local_ci.sh and the CI workflow
HELMFILE_VERSION="v1.4.2"
HELMFILE_URL="https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_linux_arm64.tar.gz"
curl -fL "${HELMFILE_URL}" | sudo tar -xz -C /usr/local/bin helmfile

echo ""
echo "==> Helmfile version:"
helmfile version

echo ""
echo "==> Adding common repos..."
helm repo add metallb https://metallb.github.io/metallb
helm repo add traefik https://traefik.github.io/charts
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo ""
echo "Done. Run 'helm repo list' to verify."
