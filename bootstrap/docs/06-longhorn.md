# 06 — Longhorn (Distributed Block Storage)

Longhorn provides replicated `PersistentVolume` storage across cluster nodes. On this
cluster it runs entirely on `pi4controller` — the Pi Zeros don't have sufficient RAM or disk
to participate in storage replication.

## Prerequisites

- K3s server and agents running (steps 01–03)
- `open-iscsi` installed on **all nodes** (handled by `install-helm.sh` on the controller;
  must be installed manually on workers)

### Install open-iscsi on workers

```bash
for i in 1 2 3 4; do
  ssh warl0ck@p$i.local "sudo apt install -y open-iscsi && sudo systemctl enable --now iscsid"
done
```

Verify on each node:
```bash
ssh warl0ck@p1.local "sudo systemctl is-active iscsid"
# Expected: active
```

## Step 1 — Install Longhorn via helmfile

If you ran `helmfile sync` in step 04, Longhorn is already installed. Verify:

```bash
kubectl -n longhorn-system get pods
```

If helmfile has not been run yet:

```bash
cd ~/raspi-k3s-cluster
helmfile sync
```

## Step 2 — Verify

```bash
kubectl -n longhorn-system get pods
# Expected: longhorn-manager, csi-attacher (×2), csi-provisioner (×2),
#           csi-resizer (×2), csi-snapshotter (×2), longhorn-ui (×1) all Running

kubectl get storageclass
# Expected: longhorn and local-path listed

kubectl -n longhorn-system get deploy
# csi-* deployments should show 2/2 READY; longhorn-ui should show 1/1
```

## Step 3 — Test a PVC

```bash
kubectl apply -f cluster/core-system/longhorn/test-pvc.yaml
kubectl get pvc -n longhorn-system
# Expected: test-pvc Bound within ~30s
```

Clean up after verifying:
```bash
kubectl delete -f cluster/core-system/longhorn/test-pvc.yaml
```

## Longhorn UI

Longhorn ships a management UI (one replica, pinned to controller):

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Open http://localhost:8080
```

From the UI you can inspect volumes, replicas, snapshots, and node disk usage.

## Configuration notes

Key decisions made in `cluster/core-system/longhorn/values.yaml`:

| Setting | Value | Reason |
|---------|-------|--------|
| `nodeSelector` | `pi4controller` | Pi Zeros lack the RAM for storage workloads |
| `defaultReplicaCount` | 1 | Single-node effective storage; no cross-node replication |
| `csi.*ReplicaCount` | 2 | Reduced from default 3 to save ~4 pods on the controller |
| `longhornUI.replicas` | 1 | One replica is sufficient for dashboard access |

## Troubleshooting

**PVC stays `Pending`**

```bash
kubectl describe pvc <name> -n <namespace>
kubectl -n longhorn-system logs -l app=longhorn-manager
```

Most common causes: `iscsid` not running on a node, or Longhorn manager not yet ready
(it can take 2–3 minutes on first install).

**CSI pods in CrashLoopBackOff after a helm upgrade**

The CSI sidecar deployments (`csi-attacher`, etc.) are created by `longhorn-driver-deployer`,
not directly by Helm. After a values change, restart the deployer to force reconciliation:

```bash
kubectl -n longhorn-system rollout restart deployment/longhorn-driver-deployer
```

If replica counts still don't update, delete the CSI deployments — the driver deployer will
recreate them with the new counts:

```bash
kubectl -n longhorn-system delete deploy csi-attacher csi-provisioner csi-resizer csi-snapshotter
kubectl -n longhorn-system rollout restart deployment/longhorn-driver-deployer
```

**Never upgrade Longhorn across multiple minor versions in one step.**
Longhorn only supports upgrading one minor version at a time (e.g. 1.7 → 1.8, not 1.7 → 1.11).
Always pin `--version` when running `helm upgrade`:

```bash
helm -n longhorn-system upgrade longhorn longhorn/longhorn --version 1.7.2 --values ...
```
