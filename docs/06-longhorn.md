# 06 — Longhorn (Distributed Block Storage)

Longhorn provides replicated persistent volumes across your cluster nodes.

> **Note:** Longhorn is heavy (~200MB RAM per node). Run it only on the Pi 4 unless
> your Pi Zeros have fast storage attached. The default replica count should be
> set to 1 for this cluster size.

## Prerequisites

```bash
# On each node that will run Longhorn
sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid
```

## Install via Helm

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultReplicaCount=1
```

## Access the Dashboard

```bash
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80
# Open http://localhost:8080
```

## Use as Default StorageClass

```bash
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass longhorn \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```
