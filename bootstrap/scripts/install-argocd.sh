#!/usr/bin/env bash
set -euo pipefail

cat << 'EOF'
==> ArgoCD Installation

This script installs ArgoCD for GitOps management of the cluster.

Features:
  - Uses Longhorn for persistent storage (ArgoCD state)
  - Accessible via Traefik Ingress (argocd.cluster.local)
  - Manages cluster/ folder as the source of truth

Prerequisites:
  - K3s cluster running
  - Longhorn installed and default StorageClass set
  - Traefik installed for Ingress
  - kubectl configured

Usage:
  bash bootstrap/scripts/install-argocd.sh

Default credentials:
  - Username: admin
  - Password: (retrieve with: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
EOF

echo ""

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo "==> ❌ kubectl not found"
    exit 1
fi

# Check Longhorn StorageClass
if ! kubectl get storageclass longhorn &>/dev/null; then
    echo "==> ❌ Longhorn StorageClass not found. Install Longhorn first."
    exit 1
fi

echo "==> Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "==> Installing ArgoCD via Helm..."
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=ClusterIP \
  --set persistence.enabled=true \
  --set persistence.storageClassName=longhorn \
  --set persistence.size=2Gi \
  --set dex.enabled=false \
  --wait \
  --timeout 5m

echo "==> Installing ArgoCD Application (cluster self-management)..."
kubectl apply -f - << 'APPEOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/TuckerWarlock/raspi-k3s-cluster
    targetRevision: main
    path: cluster/
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
APPEOF

echo "==> Installing Ingress for ArgoCD UI..."
kubectl apply -f - << 'INGRESSEOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
spec:
  ingressClassName: traefik
  rules:
  - host: argocd.cluster.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
INGRESSEOF

echo "==> Waiting for ArgoCD pods to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=3m

echo ""
echo "==> ArgoCD installation complete!"
echo ""
echo "Next steps:"
echo "  1. Get admin password:"
echo "     kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "  2. Access the UI:"
echo "     kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "     Then open: http://localhost:8080"
echo ""
echo "  3. Or access via Ingress (requires DNS setup):"
echo "     http://argocd.cluster.local"
echo ""
echo "  4. Login with:"
echo "     Username: admin"
echo "     Password: (see step 1)"
echo ""
echo "  5. Update the Application to point to your repo:"
echo "     kubectl edit application cluster -n argocd"
echo ""
