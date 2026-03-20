#!/usr/bin/env bash
set -euo pipefail

cat << 'EOF'
==> Longhorn Cleanup & Uninstall

This script completely removes Longhorn and all associated resources,
including CRDs and stuck finalizers.

Steps:
1. Helm uninstall (with --no-hooks to skip pre-delete jobs)
2. Delete Longhorn CRDs
3. Force-delete longhorn-system namespace
4. Clear any stuck finalizers
5. Verify cleanup
EOF

echo ""
echo "==> Checking if Longhorn is installed..."
if ! helm list -n longhorn-system 2>/dev/null | grep -q longhorn; then
    echo "==> ⓘ Longhorn not found in releases (may already be uninstalled)"
else
    echo "==> Found Longhorn release, uninstalling via Helm..."
    helm uninstall longhorn -n longhorn-system --no-hooks --wait --timeout=2m || true
fi

echo ""
echo "==> Deleting Longhorn CRDs (with finalizer clearing)..."
for crd in $(kubectl get crd 2>/dev/null | grep longhorn | awk '{print $1}'); do
    echo "  - Clearing finalizers on $crd..."
    kubectl patch crd "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    echo "  - Deleting $crd..."
    kubectl delete crd "$crd" --grace-period=0 --force 2>/dev/null || true
done

# Verify all CRDs are gone
if kubectl get crd 2>/dev/null | grep -q longhorn; then
    echo "==> ⚠ Some Longhorn CRDs still present, waiting and retrying..."
    sleep 5
    for crd in $(kubectl get crd 2>/dev/null | grep longhorn | awk '{print $1}'); do
        kubectl patch crd "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete crd "$crd" --grace-period=0 --force 2>/dev/null || true
    done
fi

echo ""
echo "==> Waiting for longhorn-system namespace to terminate..."
if kubectl get namespace longhorn-system &>/dev/null; then
    echo "==> Found longhorn-system namespace, forcing deletion..."
    
    # Patch namespace to clear finalizers
    echo "==> Clearing namespace finalizers..."
    kubectl get ns longhorn-system -o json 2>/dev/null | \
        sed 's/"finalizers":\[.*\]/"finalizers":\[\]/g' | \
        kubectl replace -f - 2>/dev/null || true
    
    # Force delete with grace period
    echo "==> Force-deleting namespace..."
    kubectl delete namespace longhorn-system --grace-period=0 --force 2>/dev/null || true
    
    # Wait and check
    sleep 5
    if kubectl get namespace longhorn-system &>/dev/null; then
        echo "==> ⚠ Namespace still exists, retrying finalizer clear..."
        kubectl get ns longhorn-system -o json 2>/dev/null | \
            sed 's/"finalizers":\[.*\]/"finalizers":\[\]/g' | \
            kubectl replace -f - 2>/dev/null || true
        sleep 2
    fi
fi

echo ""
echo "==> Verifying cleanup..."
if kubectl get namespace longhorn-system &>/dev/null; then
    echo "==> ⚠ longhorn-system namespace still exists (stuck on finalizers)"
    echo "==> Attempting final force-clear..."
    kubectl get ns longhorn-system -o json | \
        sed 's/"finalizers":\[.*\]/"finalizers":\[\]/g' | \
        kubectl replace -f - 2>/dev/null || true
else
    echo "==> ✓ longhorn-system namespace removed"
fi

echo ""
echo "==> Checking for remaining Longhorn CRDs..."
if kubectl get crd 2>/dev/null | grep -q longhorn; then
    echo "==> ⚠ Longhorn CRDs still present:"
    kubectl get crd | grep longhorn
else
    echo "==> ✓ No Longhorn CRDs found"
fi

echo ""
echo "==> Verifying Helm release removed..."
if helm list -n longhorn-system 2>/dev/null | grep -q longhorn; then
    echo "==> ⚠ Longhorn release still in Helm:"
    helm list -n longhorn-system | grep longhorn
else
    echo "==> ✓ Longhorn Helm release removed"
fi

echo ""
echo "==> Longhorn cleanup complete!"
echo ""
echo "To reinstall, run: bash scripts/install-longhorn.sh"
