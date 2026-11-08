# Rebuild Runbook

The single ordered procedure for building the cluster — first build or after reflashing the
Pi 4 SD card. Run the steps in order; each depends on the previous one.

The numbered guides (`01`–`07`) explain *why* each piece is configured the way it is and
hold component-specific troubleshooting. This file is the *how*.

> **Restoring after a reflash?** `setup-controller.sh` installs a nightly `k3s-backup.timer`
> that saves the K3s datastore, token, and certs to `/mnt/usb/backups/k3s-YYYY-MM-DD/`.
> If one exists, do [step 1.8](#18--optional-restore-k3s-state-from-backup) — the cluster keeps
> its old certs and token, and most of Phases 2–3 can be skipped.

> **Long-term fix:** the SD card is the weak point on power loss. Boot the Pi 4 from a USB SSD,
> or add a UPS HAT, so a brown-out doesn't corrupt the root filesystem.

**Addresses used below** (change them if yours differ):

| What | Value |
|---|---|
| Pi 4 controller (LAN) | `192.168.1.135` — reserve it on the router too |
| Pi Zeros (CNAT) | `172.19.181.1`–`.4`, gateway `172.19.181.254` |
| Traefik (MetalLB) | `192.168.1.241` |
| Pi-hole | `192.168.1.158` (separate device) |

Unless noted, run commands **on the Pi 4, from the repo root** (`cd ~/raspi-k3s-cluster`).

---

## Phase 1 — Pi 4 controller

### 1.1 — Flash the SD cards

Flash the ClusterHAT CNAT images with Raspberry Pi Imager **v1.9.6** (newer versions break
OS customisation for these images). Image choice, hostnames, and SSH settings:
[01-clusterhat-setup.md](01-clusterhat-setup.md#image-selection).

### 1.2 — Enable memory cgroups

K3s won't start without them (`install-k3s-server.sh` checks and refuses).

```bash
sudo nano /boot/firmware/cmdline.txt
# Append to the END of the existing line (do NOT press Enter):
#   cgroup_memory=1 cgroup_enable=memory
wc -l < /boot/firmware/cmdline.txt   # must print 1 — a second line stops the Pi booting
sudo reboot
```

### 1.3 — Clone the repo and run setup-controller.sh

```bash
git clone https://github.com/TuckerWarlock/raspi-k3s-cluster.git ~/raspi-k3s-cluster
cd ~/raspi-k3s-cluster
bash bootstrap/scripts/setup-controller.sh
source ~/.bash_profile
```

Installs CLI tools and configures: 1GB swap, memory sysctls, the ClusterHAT shutdown hook,
the case fan service (`clusterhat-fan.service`), and the nightly K3s backup timer. All of it
is lost on a reflash — always re-run.

### 1.4 — Set a static IP

```bash
sudo bash bootstrap/scripts/set-static-ip.sh 192.168.1.135
```

Then add a **DHCP reservation** for the Pi 4 on the router. The router hands out
`.2`–`.240`, so without a reservation it can give this address to another device.

### 1.5 — Mount the USB drive (before installing K3s)

The 32GB USB drive holds the containerd image store, local-path PVC data, and the nightly
K3s backups. It survives a reflash, but the fstab entries and systemd drop-in don't.
Mount it **before** installing K3s — otherwise K3s writes its images to the SD card first,
and the bind mount later hides them.

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL
# Expected: sda1 labelled "usb-data" (older drives may say "longhorn-data" — fine,
# the mount uses the UUID; relabel with: sudo e2label /dev/sda1 usb-data)

sudo mkdir -p /mnt/usb
echo "UUID=$(sudo blkid -s UUID -o value /dev/sda1)  /mnt/usb  ext4  defaults,nofail  0  2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /mnt/usb
sudo mkdir -p /mnt/usb/k3s-containerd
echo '/mnt/usb/k3s-containerd  /var/lib/rancher/k3s/agent/containerd  none  bind,nofail  0  0' | sudo tee -a /etc/fstab

# K3s must not start until the bind mount is up
sudo mkdir -p /etc/systemd/system/k3s.service.d
sudo tee /etc/systemd/system/k3s.service.d/usb-containerd.conf << 'EOF'
[Unit]
After=var-lib-rancher-k3s-agent-containerd.mount
Requires=var-lib-rancher-k3s-agent-containerd.mount
EOF

sudo systemctl daemon-reload && sudo mount -a
sudo df -h /mnt/usb /var/lib/rancher/k3s/agent/containerd   # both must show sda1
```

> If `mount -a` fails with "special device not found", the drive isn't plugged in.
> K3s refuses to start (by design) until it is.

Drive still laid out the old way (`/var/lib/longhorn`)? See
[Migrating an old USB layout](#migrating-an-old-usb-layout-varliblonghorn).

### 1.6 — Install the K3s server

```bash
sudo bash bootstrap/scripts/install-k3s-server.sh
```

Sets the kubelet eviction thresholds and system-reserved memory, and disables the bundled
Traefik and ServiceLB (MetalLB replaces it). Flag details: [02-k3s-server.md](02-k3s-server.md).

### 1.7 — Kubeconfig on your laptop

K3s generates new certificates on every install, so an old kubeconfig fails with
`x509: certificate signed by unknown authority`. **On your laptop:**

```bash
scp warl0ck@pi4controller.local:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i '' 's/127.0.0.1/192.168.1.135/g' ~/.kube/config   # macOS
# sed -i 's/127.0.0.1/192.168.1.135/g' ~/.kube/config    # Linux
kubectl get nodes   # pi4controller Ready
```

### 1.8 — (Optional) Restore K3s state from backup

Skip on a first-ever build. Otherwise, restore the newest backup:

```bash
ls -1d /mnt/usb/backups/k3s-*        # pick the newest
BACKUP=/mnt/usb/backups/k3s-YYYY-MM-DD

sudo systemctl stop k3s
sudo rm -f /var/lib/rancher/k3s/server/db/state.db*
sudo rm -rf /var/lib/rancher/k3s/server/tls /var/lib/rancher/k3s/server/cred
sudo cp "$BACKUP/state.db" /var/lib/rancher/k3s/server/db/state.db
sudo cp "$BACKUP/token"    /var/lib/rancher/k3s/server/token
sudo tar -xzf "$BACKUP/tls-cred.tar.gz" -C /var/lib/rancher/k3s/server
sudo systemctl start k3s

kubectl get nodes          # old nodes + workloads reappear
```

After a restore the token and CA are unchanged, so: skip 1.7, skip 2.4–2.5 if the Pi Zero
SD cards weren't reflashed, and skip 3.2–3.5 and 3.8 (ArgoCD, its apps, the local-path config, and
the TLS secrets all live in the restored datastore; ntfy's users live on its USB-backed PVC). Continue at [Phase 4](#phase-4--verify).

> Restore is not yet tested on hardware. Test a backup by hand any time:
> `sudo systemctl start k3s-backup.service && ls /mnt/usb/backups/`.

---

## Phase 2 — Pi Zero workers

### 2.1 — Underclock each Pi Zero SD card

**Before inserting each card**, mount it on your laptop and append to
`/boot/firmware/config.txt` (the FAT32 boot partition):

```ini
# Under-clocking for ClusterHAT + Pi Zero 2 W power stability
arm_freq=600
gpu_mem=16
dtoverlay=disable-wifi
dtoverlay=disable-bt
```

Without it, booting the Zeros browns out the Pi 4. Why: [03-k3s-agents.md](03-k3s-agents.md#why-underclock).

### 2.2 — Power on the hub, then the nodes one at a time

```bash
clusterctrl hub on        # required after every Pi 4 boot, or the Zeros are unreachable
for i in 1 2 3 4; do
  clusterctrl on p$i
  sleep 30                # staggered boot avoids brown-outs
done

sleep 60                  # let the last node finish booting
ip -br addr | grep ethpi  # expect ethpi1–ethpi4
for i in 1 2 3 4; do ping -c1 -W2 172.19.181.$i >/dev/null && echo "p$i up" || echo "p$i DOWN"; done
```

A node shows `DOWN` or has no `ethpiN`? See [Pi Zero unreachable](#pi-zero-unreachable).

### 2.3 — Enable memory cgroups on each node

Idempotent — skips nodes that already have the flags:

```bash
for i in 1 2 3 4; do
  ssh warl0ck@172.19.181.$i "
    grep -q cgroup_memory=1 /boot/firmware/cmdline.txt && echo 'p$i already set' || {
      sudo sed -i 's/\$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt &&
      sudo reboot
    }
  "
done
sleep 60   # wait for any reboots
```

### 2.4 — Install the K3s agent on each node

```bash
K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

for i in 1 2 3 4; do
  ssh warl0ck@172.19.181.$i "
    curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/bootstrap/scripts/install-k3s-agent.sh \
      -o install-k3s-agent.sh
    K3S_TOKEN=$K3S_TOKEN NODE_IP=172.19.181.$i bash install-k3s-agent.sh
  "
done
```

> Download, then run — don't `curl | bash`; it breaks the script's prompts.
> Re-running the installer on a Zero that already had an agent is fine: it picks up the new token.

### 2.5 — Verify and label the workers

```bash
kubectl get nodes -o wide   # pi4controller + p1–p4 all Ready
kubectl label node p1 p2 p3 p4 node-role.kubernetes.io/worker=worker hardware=pi-zero-2w
```

The `worker` label is what ArgoCD's server, redis, and repo-server schedule on. Don't taint
the Zeros — those pods have no toleration.

---

## Phase 3 — ArgoCD and the apps

### 3.1 — Install Helm and Helmfile

```bash
bash bootstrap/scripts/install-helm.sh
helmfile version   # 1.4.2
```

### 3.2 — Point local-path storage at the USB drive

K3s's `local-path-provisioner` writes PVCs to `/opt/local-path-storage` (the SD card) by
default. Redirect the controller's PVCs to USB; the Zeros keep the default.

```bash
sudo mkdir -p /mnt/usb/local-path-storage
kubectl get configmap local-path-config -n kube-system -o json | python3 -c "
import sys, json
d = json.load(sys.stdin)
cfg = json.loads(d['data']['config.json'])
cfg['nodePathMap'] = [
  {'node': 'pi4controller', 'paths': ['/mnt/usb/local-path-storage']},
  {'node': 'DEFAULT',       'paths': ['/opt/local-path-storage']}
]
d['data']['config.json'] = json.dumps(cfg)
print(json.dumps(d))
" | kubectl apply -f -

kubectl get cm local-path-config -n kube-system -o jsonpath='{.data.config\.json}' | grep mnt/usb
```

> The `last-applied-configuration` warning from `kubectl apply` is harmless.
> K3s manages this ConfigMap — re-run the `grep` after the next K3s restart to confirm it
> wasn't reset.

### 3.3 — Bootstrap ArgoCD

`helmfile.yaml` installs **only ArgoCD**; ArgoCD deploys everything else from Git.

```bash
helmfile sync
kubectl -n argocd get pods -w   # wait for all 1/1 Running (~2–4 min; images pull on the Zeros), then Ctrl-C
```

### 3.4 — Apply the root Application

```bash
kubectl apply -f cluster/argocd/root-application.yaml
kubectl -n argocd get applications -w
```

ArgoCD then deploys, roughly in this order:

| App | Deploys | Namespace |
|---|---|---|
| `metallb` | MetalLB controller + speaker | `metallb-system` |
| `metallb-config` | IPAddressPool + L2Advertisement (retries until MetalLB's CRDs exist) | `metallb-system` |
| `traefik` | Traefik ingress controller | `traefik` |
| `argocd-config` | ArgoCD ingress + the VictoriaMetrics OCI repo | `argocd` |
| `victoria-metrics` | VictoriaMetrics single-node | `monitoring` |
| `workloads` | App-of-apps for `cluster/argocd/workloads/` | `argocd` |
| `gatus` | Gatus status page | `gatus` |
| `ntfy` | ntfy push-notification server | `ntfy` |

All should reach `Synced` + `Healthy` within ~10 minutes, and Traefik gets
`EXTERNAL-IP 192.168.1.241` (`kubectl get svc -n traefik`). Anything stuck on `Unknown`,
`OutOfSync`, or `Missing`: [07-argocd.md troubleshooting](07-argocd.md#troubleshooting).

### 3.5 — Create the TLS secret for `*.cluster.local`

Traefik serves a mkcert wildcard cert so browsers trust every `*.cluster.local` site. The
secret is **not in Git**. **On your laptop**, in the folder that holds (or will hold) the cert files:

```bash
brew install mkcert nss && mkcert -install   # once per laptop — installs the local CA
mkcert "*.cluster.local"                     # once; reuse the files on later rebuilds
kubectl create secret tls cluster-local-tls \
  --cert=_wildcard.cluster.local.pem --key=_wildcard.cluster.local-key.pem -n traefik
```

Until the secret exists, Traefik serves its built-in self-signed cert.

### 3.6 — Resolve the hostnames

Add **Local DNS records on the Pi-hole** (every device then resolves them), all pointing to
`192.168.1.241`:

`argocd.cluster.local`, `vm.cluster.local`, `status.cluster.local`, `traefik.cluster.local`,
`ntfy.home.arpa`

Or, per laptop, `/etc/hosts`:

```bash
for h in argocd vm status traefik; do echo "192.168.1.241 $h.cluster.local" | sudo tee -a /etc/hosts; done
echo "192.168.1.241 ntfy.home.arpa" | sudo tee -a /etc/hosts
```

> **iPhones don't resolve `.local` names through the Pi-hole** — iOS sends them to mDNS
> (Bonjour) only. That's why ntfy, the one service the phone needs, is on `ntfy.home.arpa`
> (the name space reserved for home networks, RFC 8375). The `*.cluster.local` sites work
> from the laptop.

### 3.7 — Log in to ArgoCD

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

Open `https://argocd.cluster.local`, log in as `admin`, then change the password
(**Settings → User Info → Update Password**).

### 3.8 — Set up ntfy (certificate, users, Gatus token, iPhone)

ntfy's config is in Git, but its TLS cert, users, and tokens aren't. **On your laptop**, in
the mkcert folder from 3.5:

```bash
mkcert ntfy.home.arpa
kubectl create secret tls ntfy-tls \
  --cert=ntfy.home.arpa.pem --key=ntfy.home.arpa-key.pem -n ntfy
```

Create your user (prompts for a password) and a write-only user + token for Gatus. Users and
tokens are stored in `auth.db` on ntfy's USB-backed PVC:

```bash
kubectl -n ntfy exec -it deploy/ntfy -- ntfy user add --role=admin warl0ck

kubectl -n ntfy exec deploy/ntfy -- env NTFY_PASSWORD="$(openssl rand -base64 24)" ntfy user add gatus
kubectl -n ntfy exec deploy/ntfy -- ntfy access gatus cluster-status write-only
kubectl -n ntfy exec deploy/ntfy -- ntfy token add gatus          # prints tk_…
kubectl -n gatus create secret generic gatus-ntfy --from-literal=NTFY_TOKEN=tk_…
kubectl -n gatus rollout restart deploy/gatus                    # pick up the token
```

Test it from the laptop (use your own login):

```bash
curl -u warl0ck -d "test from the cluster" https://ntfy.home.arpa/cluster-status
```

**On the iPhone:**

1. **Trust the mkcert CA.** AirDrop `"$(mkcert -CAROOT)/rootCA.pem"` from the laptop to the
   phone → **Settings → Profile Downloaded → Install** → then **Settings → General → About →
   Certificate Trust Settings** → turn on full trust for the mkcert root.
   This lets the phone trust *any* certificate that CA signs — keep `rootCA-key.pem` on the
   laptop private.
2. **ntfy app:** **Settings → Users → Add** for `https://ntfy.home.arpa` with your login.
   Then **+ → Use another server** → `https://ntfy.home.arpa`, topic `cluster-status`.
3. Re-run the `curl` test — the notification should arrive within a few seconds.

Push reaches the phone through ntfy.sh (only the message ID passes through it), but the app
then fetches the message from `ntfy.home.arpa`, so **notifications only arrive while the
phone is on the home network** — until WireGuard/Tailscale is set up.

---

## Phase 4 — Verify

```bash
kubectl get nodes                      # all Ready
kubectl get pods -A                    # Running/Completed — no CrashLoopBackOff or OOMKilled
kubectl top nodes                      # controller under ~80% memory
kubectl -n argocd get applications     # all Synced + Healthy
systemctl status clusterhat-fan k3s-backup.timer
```

Then open `https://status.cluster.local` — every Gatus check should be green.

Before adding workloads, read [memory-management.md](memory-management.md).

### 4.1 — (Optional) Clean up leftovers from the previous cluster

After a rebuild *without* a restore, the USB drive still holds the old cluster's images and
PVC directories. Once every app is Synced + Healthy:

```bash
sudo k3s crictl rmi --prune   # remove images no running container uses

# PVC directories with no matching PV belong to the old cluster
kubectl get pv -o jsonpath='{range .items[*]}{.spec.hostPath.path}{.spec.local.path}{"\n"}{end}'
sudo ls /mnt/usb/local-path-storage/
# Delete only directories NOT in the kubectl output above:
# sudo rm -rf /mnt/usb/local-path-storage/<old-pvc-dir>
```

---

## Troubleshooting

### Pi Zero unreachable

`ssh: Could not resolve hostname pN.local`, `Destination Host Unreachable`, or no `ethpiN`
interface on the Pi 4:

1. `clusterctrl status` — the node should show `pN:1`. If not: `clusterctrl on pN`.
2. Hub off after a reboot? `clusterctrl hub on`.
3. Powered but no `ethpiN`: power-cycle that node only, then wait ~60s:
   ```bash
   clusterctrl off p3 && sleep 5 && clusterctrl on p3
   ```
4. Still nothing: check that SD card has the right per-node CNAT image (P1–P4) and the
   underclock lines from 2.1.

Use the IP (`ssh warl0ck@172.19.181.3`) if only the `.local` name fails to resolve.

### Pi Zero agents NotReady after a controller rebuild

A new K3s install generates a new token and CA. Re-running 2.4 fixes it; or swap the token
in place without reinstalling:

```bash
NEW_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
for i in 1 2 3 4; do
  ssh -o StrictHostKeyChecking=accept-new warl0ck@172.19.181.$i "
    sudo sed -i 's|K3S_TOKEN=.*|K3S_TOKEN=$NEW_TOKEN|' /etc/systemd/system/k3s-agent.service.env &&
    sudo rm -f /var/lib/rancher/k3s/agent/server-ca.crt &&
    sudo systemctl daemon-reload && sudo systemctl restart k3s-agent
  "
done
kubectl get nodes -w
```

### K3s won't start after a reboot

The systemd drop-in from 1.5 makes K3s wait for the containerd bind mount. If the fstab
lines are missing or the USB drive is unplugged, K3s stays down:

```bash
sudo df -h /mnt/usb /var/lib/rancher/k3s/agent/containerd   # both sda1?
grep -E "usb|containerd" /etc/fstab
sudo systemctl daemon-reload && sudo mount -a && sudo systemctl start k3s
```

### Migrating an old USB layout (`/var/lib/longhorn`)

Drives set up before Longhorn was removed were mounted at `/var/lib/longhorn` and may hold
Longhorn and Monday leftovers. If K3s is running, stop it first
(`sudo systemctl stop k3s && sudo /usr/local/bin/k3s-killall.sh`), then:

```bash
sudo umount /var/lib/rancher/k3s/agent/containerd /var/lib/longhorn 2>/dev/null
sudo sed -i 's|/var/lib/longhorn|/mnt/usb|g' /etc/fstab
sudo mkdir -p /mnt/usb && sudo rmdir /var/lib/longhorn
sudo e2label /dev/sda1 usb-data
sudo systemctl daemon-reload && sudo mount -a

sudo du -sh /mnt/usb/*
sudo rm -rf /mnt/usb/{engine-binaries,replicas,unix-domain-socket,longhorn-disk.cfg,ollama-models}
sudo systemctl start k3s
```

### `git pull` fails with `bad object refs/remotes/origin/HEAD`

Re-clone the repo (`rm -rf ~/raspi-k3s-cluster` and step 1.3's `git clone`). If it recurs,
check the SD card: `dmesg | grep -iE "mmc|ext4|i/o error"`.
