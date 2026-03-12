#!/usr/bin/env bash
set -euo pipefail

cat << 'EOF'
==> Longhorn Persistent Storage Setup

This script installs Longhorn on the controller node only (due to RAM constraints).
Longhorn requires ~200MB RAM per node, so it runs on pi4controller only.

Prerequisites:
  - K3s server and agents are running
  - kubectl is configured
  - Run this as a regular user (not root)

Installation Steps:
1. Install prerequisites (open-iscsi, nfs-common) on controller
2. Add Longhorn Helm repo
3. Install Longhorn with defaultReplicaCount=1
4. Set Longhorn as default StorageClass
5. Verify installation
EOF


# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "==> ❌ kubectl not found. Ensure K3s is installed and kubeconfig is configured."
    exit 1
fi

# Verify cluster is running
if ! kubectl cluster-info &> /dev/null; then
    echo "==> ❌ Cannot connect to Kubernetes cluster."
    exit 1
fi

echo "==> Installing prerequisites on controller (open-iscsi, nfs-common)..."
sudo apt install -y open-iscsi nfs-common

echo "==> Enabling and starting iscsid service..."
sudo systemctl enable --now iscsid

echo "==> Adding Longhorn Helm repository..."
helm repo add longhorn https://charts.longhorn.io
helm repo update

echo "==> Installing Longhorn via Helm (constrained to pi4controller)..."
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultReplicaCount=1 \
  --set nodeSelector."kubernetes\.io/hostname"=pi4controller \
  --wait \
  --timeout 5m

echo "==> Setting Longhorn as default StorageClass..."
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

kubectl patch storageclass longhorn \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "==> Verifying Longhorn deployment..."
kubectl get pods -n longhorn-system -o wide

echo "==> Longhorn installation complete!"
echo ""
echo "Next steps:"
echo "  - Port-forward to access dashboard: kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80"
echo "  - Then open http://localhost:8080"
echo "  - Verify PVs: kubectl get pv"
echo "  - Verify StorageClass: kubectl get storageclass"
