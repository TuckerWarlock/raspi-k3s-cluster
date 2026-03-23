# Step 06: Longhorn (Distributed Block Storage)

## Overview

Longhorn provides replicated persistent volumes across your cluster nodes. On this resource-constrained Pi 4 cluster, we use a **lightweight configuration** with replica count of 2 instead of the default 3, CSI replicas reduced from 3 to 2, and the UI disabled.

| Component | Deployment | Storage | Memory |
|-----------|-----------|---------|--------|
| Longhorn manager | Deployment on pi4controller | N/A | ~50MB |
| Longhorn CSI | DaemonSet on all nodes | N/A | ~20MB per node |
| Engine replicas | On nodes with PVCs | N/A | ~15MB per replica |

## Prerequisites

Install `open-iscsi` and `nfs-common` on each node:

```bash
# On pi4controller
sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid

# On each worker (p1–p4)
ssh warl0ck@p1.local "sudo apt install -y open-iscsi nfs-common && sudo systemctl enable --now iscsid"
ssh warl0ck@p2.local "sudo apt install -y open-iscsi nfs-common && sudo systemctl enable --now iscsid"
ssh warl0ck@p3.local "sudo apt install -y open-iscsi nfs-common && sudo systemctl enable --now iscsid"
ssh warl0ck@p4.local "sudo apt install -y open-iscsi nfs-common && sudo systemctl enable --now iscsid"
```

## Installation

Longhorn is deployed as part of the core infrastructure via helmfile:

```bash
helmfile sync
```

This installs:
- Longhorn manager and CSI components
- Helm values from `cluster/core-system/longhorn/values.yaml` (replica count: 2, UI disabled)
- Test PVC for validation in `cluster/core-system/longhorn/test-pvc.yaml`

## Verify

```bash
kubectl -n longhorn-system get pods
# Should show: longhorn-manager, longhorn-csi-attacher, longhorn-csi-provisioner, etc.

kubectl get sc
# Should show: longhorn and local-path storage classes

kubectl get pvc -A
# Any PVCs should be Bound
```

### Test Storage

Deploy a test PVC:

```bash
kubectl apply -f cluster/core-system/longhorn/test-pvc.yaml
kubectl get pvc -n longhorn-system
```

The PVC should show `Bound`. To verify replicas are working:

```bash
kubectl -n longhorn-system describe pvc test-pvc
```

## Access Longhorn Dashboard (Optional)

Port-forward to the manager:

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Open http://localhost:8080
```

From here you can view:
- Volumes and their replica status
- Node disk usage
- Snapshots and backups
- Engine process logs

## Set as Default StorageClass

Longhorn is available as a storage class immediately. To make it the default (instead of `local-path`):

```bash
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

kubectl patch storageclass longhorn \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Now any PVC without a `storageClassName` will use Longhorn automatically.

## Resource Budget

With the lightweight configuration:
- **CSI replicas:** 2 (down from 3)
- **UI:** Disabled (~8MB saved)
- **Total impact:** ~150MB on controller, ~20MB per worker node
- **Replica factor:** 2 (each volume is replicated on 2 nodes; 1 would be no HA, 3+ would be overkill)
