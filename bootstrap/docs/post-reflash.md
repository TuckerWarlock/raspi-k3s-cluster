# Post-Reflash Runbook

Complete, ordered steps to rebuild the cluster after reflashing the Pi 4 SD card.
Run these in sequence — each step depends on the previous one.

---

## Phase 1 — Pi 4 First Boot

### 1.1 — Flash and insert the SD card

Flash Raspberry Pi OS Lite (64-bit) to the SD card. Enable SSH and set hostname to
`pi4controller` in Raspberry Pi Imager before flashing.

### 1.2 — Enable cgroup memory

SSH into the Pi 4, then append cgroup flags to cmdline.txt on a **single line** (no newlines):

```bash
sudo nano /boot/firmware/cmdline.txt
# Append to the end of the existing line (do NOT press Enter):
#   cgroup_memory=1 cgroup_enable=memory
```

Verify it is still one line before saving:
```bash
cat /boot/firmware/cmdline.txt | wc -l   # must output: 1
```

Reboot, then SSH back in:
```bash
sudo reboot
```

### 1.3 — Run setup-controller.sh

Clones the repo and configures the controller (swap, sysctl, ClusterHAT):

```bash
git clone https://github.com/TuckerWarlock/raspi-k3s-cluster.git ~/raspi-k3s-cluster
cd ~/raspi-k3s-cluster
bash bootstrap/scripts/setup-controller.sh
```

This creates a 1GB swapfile and writes `/etc/sysctl.d/99-k3s-memory.conf`
(swappiness=10, OOM panic disabled). These are lost on every reflash and **must** be
re-run each time.

### 1.4 — Install K3s server

```bash
sudo bash bootstrap/scripts/install-k3s-server.sh
```

Installs K3s with kubelet eviction thresholds, system-reserved memory, and the correct
flags to disable the built-in load balancer (required for MetalLB).

### 1.5 — Refresh kubeconfig on your laptop

K3s generates new TLS certificates on every install. Your old kubeconfig will fail with
`x509: certificate signed by unknown authority`. Refresh it now:

```bash
# On your laptop:
scp warl0ck@pi4controller.local:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i '' 's/127.0.0.1/192.168.1.10/g' ~/.kube/config   # macOS
# sed -i 's/127.0.0.1/192.168.1.10/g' ~/.kube/config    # Linux
```

Verify:
```bash
kubectl get nodes
# Expected: pi4controller   Ready   ...
```

---

## Phase 2 — Pi Zero Worker Nodes

### 2.1 — Prepare each SD card before inserting

**Before inserting each Pi Zero SD card**, mount it on your laptop and add to the bottom
of `/boot/firmware/config.txt` (the FAT32 boot partition):

```ini
# Under-clocking for ClusterHAT + Pi Zero 2 W power stability
arm_freq=600
gpu_mem=16
dtoverlay=disable-wifi
dtoverlay=disable-bt
```

> Without under-clocking, powering on multiple Pi Zero 2 W nodes simultaneously will
> brown out the Pi 4 and kill its network connection.

### 2.2 — Power on nodes one at a time

From the Pi 4:
```bash
for i in 1 2 3 4; do
  clusterctrl on p$i
  sleep 30
done
```

30-second delays prevent simultaneous boot spikes that cause brownouts.

### 2.3 — Enable cgroup memory on each node

```bash
for i in 1 2 3 4; do
  ssh warl0ck@p$i.local "
    sudo sed -i 's/\$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt &&
    sudo reboot
  "
  sleep 30   # wait for reboot before moving to next node
done
```

### 2.4 — Get the node token

```bash
# On the Pi 4:
sudo cat /var/lib/rancher/k3s/server/node-token
```

Save this — you'll pass it to every agent install.

### 2.5 — Install K3s agent on each node

Run from the Pi 4, one node at a time:

```bash
for i in 1 2 3 4; do
  ssh warl0ck@p$i.local "
    curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/bootstrap/scripts/install-k3s-agent.sh \
      -o install-k3s-agent.sh
    K3S_TOKEN=<node-token> NODE_IP=172.19.181.$i bash install-k3s-agent.sh
  "
done
```

> Do NOT pipe `curl | bash` — it breaks the interactive prompts in the script.

### 2.6 — Verify nodes joined

```bash
kubectl get nodes -o wide
# Expected: pi4controller + p1, p2, p3, p4 all Ready
```

### 2.7 — Label worker nodes

```bash
kubectl label node p1 p2 p3 p4 node-role.kubernetes.io/worker=worker
kubectl label node p1 p2 p3 p4 hardware=pi-zero-2w
```

---

## Phase 3 — Bootstrap ArgoCD

### 3.1 — Install open-iscsi on workers (required for Longhorn)

Longhorn needs `iscsid` running on all nodes before it can attach volumes:

```bash
for i in 1 2 3 4; do
  ssh warl0ck@p$i.local "sudo apt install -y open-iscsi && sudo systemctl enable --now iscsid"
done
```

### 3.2 — Run helmfile sync (ArgoCD only)

`helmfile sync` now installs **only ArgoCD** — MetalLB, Traefik, and Longhorn are
deployed and managed by ArgoCD after the root Application is applied.

```bash
cd ~/raspi-k3s-cluster
helmfile sync
```

Wait for ArgoCD pods to be ready (~2 minutes):

```bash
kubectl -n argocd get pods -w
# Wait until application-controller, repo-server, redis, and server are all 1/1 Running
```

### 3.3 — Apply the ArgoCD ingress and root Application

The ingress exposes `argocd.cluster.local` via Traefik (which ArgoCD is about to deploy):

```bash
kubectl apply -f cluster/argocd/argocd-ingress.yaml
kubectl apply -f cluster/argocd/root-application.yaml
```

The root Application tells ArgoCD to watch `cluster/argocd/addons/` and deploy everything
defined there. ArgoCD will now install (in roughly this order, automatically):

| App | What it deploys | Namespace |
|-----|----------------|-----------|
| `metallb` | MetalLB controller + speaker | `metallb-system` |
| `metallb-config` | IPAddressPool + L2Advertisement | `metallb-system` |
| `traefik` | Traefik ingress controller | `traefik` |
| `longhorn` | Longhorn storage + CSI | `longhorn-system` |
| `prometheus` | Prometheus + node-exporter | `monitoring` |
| `loki` | Loki log aggregation | `monitoring` |
| `promtail` | Promtail log shipping | `monitoring` |

> **`metallb-config` will retry automatically** — it applies the IP pool only after MetalLB
> CRDs are ready. No manual intervention needed.

Watch all applications reach `Synced` + `Healthy`:

```bash
kubectl -n argocd get applications -w
```

Traefik gets its `EXTERNAL-IP` from MetalLB once both are healthy:

```bash
kubectl get svc -n traefik
# EXTERNAL-IP should show 192.168.1.241
```

### 3.4 — Update /etc/hosts on your laptop (if needed)

If the Traefik IP has changed or this is a fresh laptop:

```bash
# Replace 192.168.1.241 with your actual Traefik EXTERNAL-IP if different
echo "192.168.1.241 argocd.cluster.local" | sudo tee -a /etc/hosts
echo "192.168.1.241 prometheus.cluster.local" | sudo tee -a /etc/hosts
echo "192.168.1.241 grafana.cluster.local" | sudo tee -a /etc/hosts
```

---

## Phase 4 — ArgoCD First Login

### 4.1 — Get the initial admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo
```

Open `http://argocd.cluster.local` → log in as `admin` with the above password.

> Change the password after first login: **Settings → User Info → Update Password.**

---

## Phase 5 — Reconnect Pi Zero Agents (after token change)

Every K3s reinstall generates a new node token. Existing Pi Zero agents will fail to
connect until their token is updated. If agents are stuck `NotReady`:

```bash
NEW_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

for i in 1 2 3 4; do
  ssh -o StrictHostKeyChecking=accept-new warl0ck@p$i.local "
    sudo sed -i 's|K3S_TOKEN=.*|K3S_TOKEN=$NEW_TOKEN|' /etc/systemd/system/k3s-agent.service.env &&
    sudo rm -f /var/lib/rancher/k3s/agent/server-ca.crt &&
    sudo systemctl daemon-reload &&
    sudo systemctl restart k3s-agent
  "
  echo "==> p$i updated"
done

kubectl get nodes -w
```

---

## Phase 6 — Verify the Cluster is Healthy

```bash
# All nodes Ready
kubectl get nodes

# All pods Running / Completed (no CrashLoopBackOff or OOMKilled)
kubectl get pods -A

# Memory usage within safe range (target: < 80%)
kubectl top nodes

# ArgoCD applications Synced + Healthy
kubectl -n argocd get applications
```

Refer to `bootstrap/docs/memory-management.md` for safe deployment procedures and
memory budgets before adding any new workloads.
