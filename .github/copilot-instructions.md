# Copilot Instructions

This repository provisions and documents a K3s Kubernetes cluster on a Raspberry Pi 4 controller with four Pi Zero 2 W worker nodes via a ClusterHAT v2.5.

## Setup Progress

✅ **Completed:**
- 01 — ClusterHAT hardware setup
- 02 — K3s server (control plane)
- 03 — K3s agents (p1–p4 workers)
- 04 — MetalLB (load balancer)
- 05 — Traefik ingress controller
- 06 — Longhorn (distributed block storage)
- 07 — ArgoCD (GitOps management)
- 08 — Prometheus + Grafana (monitoring)

🔄 **In Progress:**
- 09 — Loki + Promtail (logging)
- 10 — Sample workload (GitOps validation)
- 11 — Longhorn backup strategy
- (12 — cert-manager + Let's Encrypt - deferred)

## Repo Structure

```
bootstrap/
  scripts/          # Setup scripts (run on Pi hardware)
    install-*.sh   # K3s, Helm, Longhorn, ArgoCD installers
  docs/             # Step-by-step setup guides (01-11)
cluster/
  core-system/      # Core Kubernetes infrastructure
    metallb/        # Load balancer (IPAddressPool + L2Advertisement)
    traefik/        # Ingress controller (Helm values)
    longhorn/       # Block storage (Helm values + test PVC)
  argocd/           # GitOps management (Application CRD + Ingress)
  monitoring/       # Prometheus + Grafana (TBD: step 08)
  logging/          # Loki + Promtail (TBD: step 09)
  workloads/        # User applications (TBD: step 10)
README.md           # Project overview
```

## Implementation Notes (Steps 08-11)

**Step 08 — Prometheus + Grafana:**
- Prometheus deployed on pi4controller with 15-day retention (Longhorn PVC)
- Node-exporter DaemonSet on all nodes (lightweight metric collection)
- Grafana dashboard on controller, persisted to Longhorn
- Traefik Ingress: `prometheus.cluster.local`, `grafana.cluster.local`

**Step 09 — Loki + Promtail:**
- Loki (single-process mode) on controller, Longhorn chunk storage
- Promtail agents on all nodes, logs → Loki
- Access via Grafana datasource or standalone UI

**Step 10 — Sample Workload:**
- Deploy test app (e.g., nginx with PersistentVolume)
- Verify ArgoCD auto-syncs from cluster/ folder
- Proves full GitOps pipeline functional

**Step 11 — Longhorn Backup:**
- Configure backup targets (local or S3)
- Set snapshot retention policies
- Document restore procedures

**Step 12 — Certificates (Deferred):**
- Currently: self-signed certs via Traefik (working fine, Firefox shows warning)
- Future: cert-manager + Let's Encrypt when external DNS available

## Network Layout

| Layer | Interface | Subnet | Notes |
|-------|-----------|--------|-------|
| LAN | eth0 | 192.168.1.0/24 | Controller static IP: 192.168.1.10 |
| CNAT | usb0 | 172.19.181.0/24 | Controller gateway: 172.19.181.254; p1–p4: .1–.4 |
| Cluster pods | flannel | 10.42.0.0/16 | K3s default |
| Cluster services | — | 10.43.0.0/16 | K3s default |
| MetalLB pool | LAN | 192.168.1.241–254 | Outside router DHCP range (.2–.240) |

K3s agents use `--node-ip 172.19.181.x --flannel-iface usb0` so pod traffic routes through the CNAT interface, not the Pi 4's LAN.

## Node Roles & Constraints

- **pi4controller** — control plane only; system components pinned here via `nodeSelector: kubernetes.io/hostname: pi4controller`
- **p1–p4** — workers labeled `node-role.kubernetes.io/worker=worker` and `hardware=pi-zero-2w`; 512MB RAM each — keep workloads light
- Traefik and MetalLB speakers are restricted to pi4controller (Pi Zeros have no LAN interface for L2 advertisement)

## Documentation Requirements

Every change to this repo must have supporting documentation. The rule is simple: if you add or change something, update the relevant doc alongside it in the same commit/PR.

| Change type | Required documentation |
|---|---|
| New or updated Kubernetes manifest | Update `README.md` repo structure if a new directory is added; add/update the relevant setup guide in `bootstrap/docs/` if the change affects a setup step |
| New or updated Helm values | **First**, fetch the chart's upstream `values.yaml` from the source repository (GitHub or Artifact Hub) and verify the exact key names before writing anything — silently-ignored keys are a common failure mode. Then comment the values file explaining non-obvious settings; update the corresponding `bootstrap/docs/` guide |
| New or updated GitHub Actions workflow | Add a comment block at the top of the workflow file describing what it does and when it runs; update `README.md` if it affects the CI story |
| New or updated bootstrap script | Update the script's internal usage header (`cat << 'EOF' ... EOF`); update the corresponding `bootstrap/docs/` step guide; update the scripts table in `README.md` |
| New `local_ci.sh` behaviour | Keep the script's top-of-file comment block accurate |
| New tooling added (e.g. Pluto, kubeconform) | Add it to the **Tools Used** section in `README.md` |
| Architecture or network changes | Update `bootstrap/docs/architecture.md` and the network table in `README.md` |

When Copilot makes any of the above changes, it must also apply the corresponding documentation update in the same response — do not leave documentation as a follow-up suggestion.

## Helm Values Workflow

Before creating or editing any `values.yaml` file, **always verify key names against the upstream chart**. Helm silently ignores unknown keys — wrong key names are invisible failures that leave the cluster at chart defaults.

1. Locate the chart source (check the existing `helm repo add` command in the relevant install script or doc to find the repo URL).
2. Fetch the upstream `values.yaml` directly from GitHub (e.g. `https://raw.githubusercontent.com/<org>/<repo>/refs/heads/main/charts/<chart>/values.yaml`) or via `helm show values <repo>/<chart> --version <version>`.
3. Confirm the exact key path for every setting you intend to set.
4. Only then write or update the `values.yaml` in this repo.

When running `helm upgrade`, **always pin `--version <current-version>`** unless you are intentionally upgrading the chart. Omitting it pulls the latest chart and can cause a version jump that breaks the release.



All scripts use `#!/usr/bin/env bash` and `set -euo pipefail`. Output uses `==> ` section prefixes. Heredocs use `<< 'EOF'` (no variable expansion inside).

| Script | Run as | Notes |
|--------|--------|-------|
| `setup-controller.sh` | user (no sudo) | Sources sudo internally where needed |
| `install-k3s-server.sh` | `sudo bash` | Requires cgroups in cmdline.txt first |
| `install-k3s-agent.sh` | user | Accepts `K3S_TOKEN` and `NODE_IP` env vars; do NOT pipe via curl (breaks prompts) |
| `install-helm.sh` | user (no sudo) | Helm repos are per-user — sudo breaks them |
| `set-static-ip.sh` | `sudo bash` | Requires IP as argument: `sudo bash set-static-ip.sh 192.168.1.10` |

## Key K3s Flags

```bash
# Server (install-k3s-server.sh)
--write-kubeconfig-mode 644   # kubectl without sudo
--disable traefik             # install via Helm instead
--disable servicelb           # required — conflicts with MetalLB
```

## Applying Manifests

```bash
kubectl apply -f manifests/metallb/ipaddresspool.yaml
kubectl apply -f manifests/metallb/l2advertisement.yaml

helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --values manifests/traefik/values.yaml --wait
```

## Critical Hardware Notes

- **Power supply:** Pi 4 requires 5V/3A via USB-C to USB-C cable. USB-A to USB-C under-delivers voltage even on 2A bricks.
- **ClusterHAT shutdown order:** Always `clusterctrl off` before rebooting the Pi 4. `setup-controller.sh` installs a `clusterctrl-off.service` systemd unit that handles this automatically.
- **Node boot order:** Power on p1–p4 one at a time with 30s delays (`clusterctrl on p$i && sleep 30`) — simultaneous boot spikes cause brownouts.
- **Pi Zero 2 W under-clocking:** Each node's SD card needs these lines in `/boot/firmware/config.txt` before first insert: `arm_freq=600`, `gpu_mem=16`, `dtoverlay=disable-wifi`, `dtoverlay=disable-bt`.

## cmdline.txt Rule

`/boot/firmware/cmdline.txt` must remain a **single line** with no trailing newline. A second line causes boot failure. Append cgroup flags like this:

```bash
# Verify it's one line before saving:
cat /boot/firmware/cmdline.txt | wc -l   # must be 1
```

## Kubeconfig (Laptop Access)

```bash
scp warl0ck@pi4controller.local:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i '' 's/127.0.0.1/192.168.1.10/g' ~/.kube/config   # macOS
sed -i 's/127.0.0.1/192.168.1.10/g' ~/.kube/config      # Linux
```

Re-run after every K3s reinstall — certs change on each install.

## Token Swap (After Controller Reflash)

When the Pi 4 is reflashed, update all agent nodes:

```bash
NEW_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
for i in 1 2 3 4; do
  ssh -o StrictHostKeyChecking=accept-new warl0ck@p$i.local "
    sudo sed -i 's|K3S_TOKEN=.*|K3S_TOKEN=$NEW_TOKEN|' /etc/systemd/system/k3s-agent.service.env &&
    sudo rm -f /var/lib/rancher/k3s/agent/server-ca.crt &&
    sudo systemctl daemon-reload && sudo systemctl restart k3s-agent
  "
done
```
