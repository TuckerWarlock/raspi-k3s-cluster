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

## USB Storage Expansion

The Pi 4's 29 GB SD card cannot hold both Longhorn volume data and the K3s containerd
image cache at the same time. A 32 GB USB flash drive solves this: Longhorn volumes live
at the root of the USB mount, and the containerd image cache lives in a subdirectory that
is bind-mounted to its expected K3s path.

### Disk layout after setup

| Mount path | Device | What lives here |
|------------|--------|----------------|
| `/var/lib/longhorn` | USB flash drive | Longhorn volume replicas |
| `/var/lib/rancher/k3s/agent/containerd` | USB (bind mount) | K3s container images (~13 GB) |
| `/` | SD card | OS, K3s binaries, SQLite, pod writable layers |

### One-time setup (fresh install)

**Format and mount the USB drive:**

```bash
# Verify device name first
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL

# Format (replace /dev/sda1 with actual device)
sudo mkfs.ext4 -L longhorn-data /dev/sda1

# Add fstab entry and mount
sudo mkdir -p /var/lib/longhorn
echo "UUID=$(sudo blkid -s UUID -o value /dev/sda1)  /var/lib/longhorn  ext4  defaults,nofail  0  2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /var/lib/longhorn
```

**Set up the containerd bind mount:**

```bash
sudo mkdir -p /var/lib/longhorn/k3s-containerd

echo '/var/lib/longhorn/k3s-containerd  /var/lib/rancher/k3s/agent/containerd  none  bind,nofail  0  0' | sudo tee -a /etc/fstab

sudo mkdir -p /etc/systemd/system/k3s.service.d
sudo tee /etc/systemd/system/k3s.service.d/usb-containerd.conf << 'EOF'
[Unit]
After=var-lib-rancher-k3s-agent-containerd.mount
Requires=var-lib-rancher-k3s-agent-containerd.mount
EOF

sudo systemctl daemon-reload && sudo mount -a
```

The `After=` / `Requires=` drop-in ensures k3s never starts before the USB bind mount is
active — so a reboot with the drive unplugged will stall k3s rather than start it against
the bare SD card directory.

### Migrating an existing install (rsync → compact → move)

Run this if Longhorn was already installed and the containerd cache already exists on the
SD card.

```bash
# 1. Scale down all consumers and stop k3s
kubectl scale deploy --all -n monday --replicas=0
kubectl scale deploy --all -n longhorn-system --replicas=0
sudo systemctl stop k3s

# 2. Compact Longhorn sparse files on USB
#    rsync without --sparse expands replica image holes; fallocate reclaims them
sudo find /var/lib/longhorn -type f -size +1M | xargs sudo fallocate --dig-holes 2>/dev/null
df -h /var/lib/longhorn   # usage should drop from ~13 GB to ~1 GB

# 3. Clean old SD card Longhorn data hidden under the USB mount
sudo umount /var/lib/longhorn
sudo rm -rf /var/lib/longhorn/*
sudo mount /var/lib/longhorn

# 4. Copy containerd cache to USB (~10 min over USB 2.0)
sudo mkdir -p /var/lib/longhorn/k3s-containerd
sudo rsync -a /var/lib/rancher/k3s/agent/containerd/ /var/lib/longhorn/k3s-containerd/

# 5. Add fstab bind mount + systemd drop-in (see "One-time setup" above)

# 6. Mount and clean old SD card containerd data hidden under the bind mount
sudo mount /var/lib/rancher/k3s/agent/containerd
sudo umount /var/lib/rancher/k3s/agent/containerd
sudo rm -rf /var/lib/rancher/k3s/agent/containerd/*
sudo mount /var/lib/rancher/k3s/agent/containerd

# 7. Verify — SD card should be ~40–45% used; USB ~14 GB used
df -h / && df -h /var/lib/longhorn

# 8. Start k3s and scale Longhorn + workloads back up
sudo systemctl start k3s
```

### After a reflash

The USB drive survives a Pi 4 reflash. After re-running `install-k3s-server.sh`:

1. Plug in the USB drive.
2. Re-add both fstab entries (USB mount + bind mount) — see "One-time setup" above.
3. Re-create the systemd drop-in at `/etc/systemd/system/k3s.service.d/usb-containerd.conf`.
4. `sudo systemctl daemon-reload && sudo mount -a`
5. Start k3s — it finds its full image cache on the USB and starts immediately.

See also `bootstrap/docs/post-reflash.md` Phase 1.5.

---

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
