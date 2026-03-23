#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cat <<'EOFMESSAGE'
==> Helm reset

This script uninstalls the currently deployed Helm releases (including ArgoCD), removes the associated namespaces, runs the Longhorn cleanup helper, and clears all Helm repositories to simulate a fresh environment.
EOFMESSAGE

echo ""

declare -A RELEASES=(
  [metallb]=metallb-system
  [traefik]=traefik
  [argocd]=argocd
)

for name in "${!RELEASES[@]}"; do
  namespace="${RELEASES[$name]}"
  if helm -n "$namespace" list --short | grep -q "^$name$" 2>/dev/null; then
    echo "==> Uninstalling $name from namespace $namespace"
    helm uninstall "$name" -n "$namespace" --no-hooks --wait --timeout=3m || true
  else
    echo "==> $name release not present in namespace $namespace"
  fi
done

echo ""
echo "==> Running dedicated Longhorn cleanup helper"
bash "$SCRIPT_DIR/cleanup-longhorn.sh"

echo ""
declare -a NAMESPACES=(
  metallb-system
  traefik
  argocd
  monitoring
  longhorn-system
)

for ns in "${NAMESPACES[@]}"; do
  echo "==> Deleting namespace $ns"
  kubectl delete namespace "$ns" --ignore-not-found --wait --timeout=2m || true
done

echo ""
echo "==> Clearing Helm repositories"
mapfile -t helm_repos < <(helm repo list | tail -n +2 | awk '{print $1}')
if [ "${#helm_repos[@]}" -gt 0 ]; then
  for repo in "${helm_repos[@]}"; do
    echo "==> Removing repo $repo"
    helm repo remove "$repo" || true
  done
else
  echo "==> No Helm repositories configured"
fi

echo ""
echo "==> Removing Helm cache and config directories"
rm -rf "$HOME/.cache/helm" "$HOME/.local/share/helm" "$HOME/.config/helm" || true

echo ""
echo "==> Helm reset complete"
echo "You can now re-bootstrap the cluster by rerunning the setup scripts and \`helmfile sync\` (see bootstrap/docs/07-reset-bootstrap.md)."
