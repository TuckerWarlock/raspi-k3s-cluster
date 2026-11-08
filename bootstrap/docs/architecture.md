# Architecture & Tech Stack

This document captures the hardware layout, networking design, software stack decisions,
and workload placement strategy for this cluster.

Reference these:
- https://blog.zwindler.fr/en/2026/01/27/installing-a-cluster-hat-with-raspberry-pi-5-and-pi-zero/
- https://dev.to/subnetsavy/how-to-build-a-home-kubernetes-cluster-with-raspberry-pi-2025-guide-204o

---

## Hardware

| Node | Device | Role | RAM | Storage |
|------|--------|------|-----|---------|
| `pi4controller` | Raspberry Pi 4 | K3s control plane + system workloads | 4GB | 29 GB SD card + 32 GB USB flash drive (`/mnt/usb`) |
| `p1` | Raspberry Pi Zero 2 W | K3s worker | 512MB | 32 GB SD card (~28 GB usable) |
| `p2` | Raspberry Pi Zero 2 W | K3s worker | 512MB | 32 GB SD card (~28 GB usable) |
| `p3` | Raspberry Pi Zero 2 W | K3s worker | 512MB | 32 GB SD card (~28 GB usable) |
| `p4` | Raspberry Pi Zero 2 W | K3s worker | 512MB | 32 GB SD card (~28 GB usable) |

The Pi Zeros are attached via a [ClusterHAT v2](https://clusterctrl.com/) on the Pi 4.
Power and USB connectivity to all four nodes is managed by the HAT.

---

## Network

```
Home LAN (192.168.1.0/24 — router DHCP hands out .2–.240)
 ├── Pi-hole                → 192.168.1.158   (separate Pi Zero; DNS + *.cluster.local records)
 ├── MetalLB pool           → 192.168.1.241–.254 (Traefik = .241)
 └── Raspberry Pi 4 controller
      ├── eth0  → 192.168.1.135   (static, set-static-ip.sh; reserve it on the router)
      └── br0   → 172.19.181.254  (CNAT gateway for Pi Zero nodes; one ethpiN per node)
           ├── p1  172.19.181.1
           ├── p2  172.19.181.2
           ├── p3  172.19.181.3
           └── p4  172.19.181.4
```

**CNAT (Cluster NAT):** Pi Zero nodes route all traffic through the Pi 4 controller.
They have no direct LAN or WiFi connection — all network access goes via the HAT's USB
interface. The Pi 4 acts as their gateway.

**K3s pod/service networking:** Flannel (K3s default CNI). Agents are joined with
explicit `--node-ip` and `--flannel-iface usb0` to ensure traffic uses the correct interface
across the CNAT subnet.

> **Phase 2:** Replace Flannel with [Cilium](https://cilium.io/) for eBPF-based networking
> and Hubble network observability once the cluster is stable.

---

## Kubernetes Distribution

**[K3s](https://k3s.io/)** — lightweight Kubernetes for ARM/edge hardware.

Chosen over full kubeadm because:
- Pi Zero 2 W has 512MB RAM; full K8s worker components exceed that under load
- K3s agent idles at ~150MB, full K8s worker at ~600MB+
- K3s is production-grade (same API, same kubectl/helm/CNI tooling)
- Ships with useful defaults (metrics-server, Flannel, CoreDNS, local-path storage)

---

## Software Stack

### Installed by K3s (no action required)

| Component | Purpose |
|-----------|---------|
| **metrics-server** | Powers `kubectl top nodes/pods` |
| **Flannel** | CNI pod networking |
| **local-path-provisioner** | Default StorageClass; controller PVCs go to the USB drive |
| **CoreDNS** | Cluster DNS |
| **Gateway API CRDs** | Installed by K3s v1.37+; charts must not ship older copies |

K3s's bundled Traefik and ServiceLB are **disabled** (`--disable traefik --disable servicelb`).

### Deployed from this repo

| Component | Purpose | How | Runs on |
|-----------|---------|-----|---------|
| **ArgoCD** | GitOps control plane — App of Apps | `helmfile sync` | app-controller on controller; server, redis, repo-server on workers |
| **MetalLB** | Bare-metal LoadBalancer via Layer 2 ARP | ArgoCD (Helm) | controller only — Pi Zeros have no LAN interface |
| **Traefik** | Ingress controller, mkcert wildcard TLS | ArgoCD (Helm) | controller |
| **VictoriaMetrics** | Metrics storage + scraping (single-node) | ArgoCD (Helm, OCI) | controller |
| **Gatus** | Status page and uptime checks | ArgoCD (manifests) | controller |
| **ntfy** | Push notifications to the iPhone (`ntfy.home.arpa`) | ArgoCD (manifests) | controller |

### Planned

| Component | Purpose | Notes |
|-----------|---------|-------|
| **vmalert** | Alert rules on VictoriaMetrics | Brings back the old memory-pressure alerts |
| **WireGuard / Tailscale** | Remote access | |
| **SOPS + age** | Encrypted secrets in Git | Not set up — today's secrets (`cluster-local-tls`, `ntfy-tls`, `gatus-ntfy`) are created by hand |
| **Cilium + Hubble** | eBPF CNI + network observability | Replaces Flannel; install K3s with `--flannel-backend=none` |
| **cert-manager** | Let's Encrypt certificates | Deferred — the mkcert wildcard works for a homelab |

---

## Memory Management

The Pi 4 controller runs all system workloads on 4GB RAM. Three layers prevent
OOM-induced SD card corruption:

1. **Swap (1GB)** — last-resort buffer; created by `setup-controller.sh`
2. **Kubelet eviction** — soft evict at 512Mi available, hard evict at 300Mi available
3. **Accurate resource requests** — all components sized to reflect real usage

See [memory-management.md](memory-management.md) for the full budget and safe deployment
procedure.

---

## Workload Placement

Pi Zero nodes have 512MB RAM each. System workloads that require the LAN interface or
exceed 512MB stay on the Pi 4 controller. Lighter system components and all application
workloads schedule across the Pi Zero workers.

### Pi 4 Controller — heavy / LAN-dependent workloads

| Workload | Reason pinned to controller |
|----------|-----------------------------|
| K3s control plane | Must run on server node |
| MetalLB | L2 ARP advertisement requires LAN (eth0) — Pi Zeros have no LAN |
| Traefik | LoadBalancer Service type requires MetalLB, which needs eth0 |
| ArgoCD application-controller | 512Mi memory limit = entire Pi Zero RAM budget |
| VictoriaMetrics | PVC on USB drive via local-path; 256Mi limit |
| Gatus | Needs LAN access for Pi-hole / k3s API checks; PVC on USB drive |
| ntfy | Relays iOS push via ntfy.sh over the LAN; users/tokens on a USB-backed PVC |

All controller-pinned workloads use:
```yaml
nodeSelector:
  kubernetes.io/hostname: pi4controller
```

### Pi Zero Nodes (p1–p4) — lightweight system + application workloads

| Workload | Notes |
|----------|-------|
| ArgoCD server | API + UI server; ~80Mi idle |
| ArgoCD redis | Session cache; ~15Mi idle |
| ArgoCD repo-server | Git repo fetch + manifest rendering; ~60Mi idle |
| Application workloads | Schedule freely across workers |

Workers use:
```yaml
nodeSelector:
  node-role.kubernetes.io/worker: "worker"
```

Nodes are labeled to control scheduling (the labels are applied in [rebuild.md step 2.5](rebuild.md#25--verify-and-label-the-workers)).
**Don't taint the Zeros** — the ArgoCD components there have no toleration.

**Use the worker label in application workloads:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      # Run only on worker nodes (not controller)
      nodeSelector:
        node-role.kubernetes.io/worker: "worker"
      containers:
      - name: app
        image: my-app:latest
```

**Hostname-based selectors** (used by system components) — forces workloads to specific nodes:

```yaml
nodeSelector:
  kubernetes.io/hostname: pi4controller  # Only on controller
  # OR
  kubernetes.io/hostname: p1             # Only on p1
```

Use role labels for application workloads (flexible scheduling across workers).
Use hostname selectors for system components that must run on specific nodes.

---

## GitOps Flow

This repo is the single source of truth for cluster state.

```
helmfile.yaml               # installs ArgoCD (the only manual Helm release)
cluster/argocd/
  root-application.yaml     # applied once by hand → manages addons/
  addons/                   # one Application per infrastructure component
  workloads/                # one Application per app in workloads/
cluster/core-system/        # Helm values + raw config for MetalLB and Traefik
cluster/monitoring/         # VictoriaMetrics values
workloads/<app>/            # app manifests + kustomization.yaml
bootstrap/                  # scripts and docs run by hand on the Pis
```

**Deployment flow:**
1. Changes merged to `main`
2. ArgoCD notices within 5 minutes (`timeout.reconciliation: 300s`) and syncs the cluster
3. No manual `kubectl apply` for ongoing changes — Git is the source of truth

Details and troubleshooting: [07-argocd.md](07-argocd.md).

---

## Decisions Log

Capturing key decisions and the reasoning behind them.

| Decision | Chosen | Rejected | Reason |
|----------|--------|----------|--------|
| K8s distribution | K3s | kubeadm (full K8s) | Pi Zero 2 W only has 512MB RAM |
| CNI | Flannel (K3s default) | Calico, Weave | Simplicity; Cilium planned for Phase 2 |
| Ingress | Traefik v3 (Helm chart via ArgoCD; K3s bundle disabled) | ingress-nginx | ingress-nginx officially retired March 2026 |
| GitOps | ArgoCD | Flux | Familiarity; UI visibility useful for homelab |
| Secrets | SOPS + age (planned) | Bitnami Sealed Secrets, ESO | No external backend needed; simple file encryption; no Bitnami dependency |
| Metrics | VictoriaMetrics single-node + metrics-server | kube-prometheus-stack, Prometheus + Grafana + Loki | ~120Mi, vs ~350Mi for Prometheus alone plus Loki and Grafana in the old budget |
| Load balancer | MetalLB (Layer 2) | Cloud LB | Bare-metal; Layer 2 ARP works on home LAN |
| Storage | local-path (K3s default) | Longhorn | Longhorn too heavy; revisit if persistent storage needs grow |
| Chart source for VictoriaMetrics | OCI (`ghcr.io`) | HTTP Helm repo | The 3.6MB HTTP `index.yaml` took the Pi Zero repo-server ~74s, past ArgoCD's 60s deadline |
| Pi 4 data | USB drive at `/mnt/usb` | SD card only | SD card corrupts on power loss; images, PVCs, and backups live on USB |
| ntfy hostname | `ntfy.home.arpa` | `ntfy.cluster.local` | iOS resolves `.local` only via mDNS, so a Pi-hole record would never be used by the phone |
