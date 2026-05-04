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
| `controller` | Raspberry Pi 4 | K3s control plane + system workloads | 4GB | 29 GB SD card + 32 GB USB flash drive |
| `p1` | Raspberry Pi Zero 2 W | K3s worker | 512MB | 32 GB SD card (~28 GB usable) |
| `p2` | Raspberry Pi Zero 2 W | K3s worker | 512MB | 32 GB SD card (~28 GB usable) |
| `p3` | Raspberry Pi Zero 2 W | K3s worker | 512MB | 32 GB SD card (~28 GB usable) |
| `p4` | Raspberry Pi Zero 2 W | K3s worker | 512MB | 32 GB SD card (~28 GB usable) |

The Pi Zeros are attached via a [ClusterHAT v2](https://clusterctrl.com/) on the Pi 4.
Power and USB connectivity to all four nodes is managed by the HAT.

---

## Network

```
Home LAN (192.168.x.x — DHCP assigned by router)
 └── Raspberry Pi 4 controller
      ├── eth0  → 192.168.1.x    (LAN, static DHCP reservation on router)
      └── usb0  → 172.19.181.254  (CNAT gateway for Pi Zero nodes)
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
- Ships with useful defaults (metrics-server, Traefik, Flannel, local-path storage)

---

## Software Stack

### Installed by K3s (no action required)

| Component | Purpose |
|-----------|---------|
| **metrics-server** | Powers `kubectl top nodes/pods` — sufficient for resource visibility |
| **Traefik v3** | Ingress controller and reverse proxy |
| **Flannel** | CNI pod networking |
| **local-path-provisioner** | Default StorageClass for PVCs backed by node-local storage |
| **CoreDNS** | Cluster DNS |

### Installed separately (via Helm / manifests)

| Component | Purpose | Runs on |
|-----------|---------|---------|
| **ArgoCD** | GitOps control plane — App of Apps pattern | controller (app-controller) + workers (server, redis, repo-server) |
| **MetalLB** | Bare-metal LoadBalancer via Layer 2 ARP | Pi 4 (controller only — Pi Zeros have no LAN interface) |
| **SOPS + age** | Secret encryption for GitOps — secrets committed encrypted to git | N/A (client tooling) |

### Optional / Phase 2

| Component | Purpose | Notes |
|-----------|---------|-------|
| **Cilium + Hubble** | eBPF CNI + network observability | Replaces Flannel; install K3s with `--flannel-backend=none` |
| **Headlamp** | Lightweight Kubernetes web UI | Surfaces metrics-server data |
| **cert-manager** | TLS certificate management (Let's Encrypt) | Deferred — self-signed mkcert wildcard cert works fine for homelab |

---

## Memory Management

The Pi 4 controller runs all system workloads on 4GB RAM. Three layers prevent
OOM-induced SD card corruption:

1. **Swap (1GB)** — last-resort buffer; created by `setup-controller.sh`
2. **Kubelet eviction** — soft evict at 512Mi available, hard evict at 300Mi available
3. **Accurate resource requests** — all components sized to reflect real usage

See `bootstrap/docs/memory-management.md` for the full budget, safe deployment
procedure, and post-reflash restore steps.

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
| Ollama | hostPath mount at `/var/lib/longhorn/ollama-models` on USB drive |
| Open WebUI | 1536Mi memory limit — too heavy for Pi Zero |
| Prometheus | High cardinality scrape; remote-write persistence |

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

Nodes are labeled and optionally tainted to control scheduling.

**Setup labels** (run from controller after agents join):

```bash
# Label all workers
kubectl label node p1 p2 p3 p4 node-role.kubernetes.io/worker=worker
kubectl label node p1 p2 p3 p4 hardware=pi-zero-2w

# Optional: taint to prevent system pods from scheduling
kubectl taint node p1 p2 p3 p4 hardware=pi-zero-2w:NoSchedule
```

**Use labels in application workloads** (optional but recommended):

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
      
      # If tainted, add toleration
      tolerations:
      - key: hardware
        operator: Equal
        value: pi-zero-2w
        effect: NoSchedule
      
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

This repo serves as the single source of truth for cluster state.

```
raspi-k3s-cluster/ (this repo)
  cluster/
    bootstrap/    # ArgoCD install — applied once by hand to bootstrap
    apps/         # ArgoCD Application manifests (App of Apps root)
  charts/         # Helm values files per application
  manifests/      # Raw Kubernetes manifests
  scripts/        # One-time setup scripts (K3s install, Helm install, etc.)
  docs/           # This documentation
```

**Deployment flow:**
1. Changes merged to `main`
2. ArgoCD detects drift and syncs the cluster to match repo state
3. No manual `kubectl apply` for ongoing changes — git is the source of truth

**Secrets flow (SOPS + age):**
1. Secrets are encrypted with `sops --encrypt` using an age public key before committing
2. The age private key lives as a K8s secret on the cluster (applied once, never committed)
3. ArgoCD decrypts secrets at sync time via a SOPS plugin sidecar on the repo-server

---

## Decisions Log

Capturing key decisions and the reasoning behind them.

| Decision | Chosen | Rejected | Reason |
|----------|--------|----------|--------|
| K8s distribution | K3s | kubeadm (full K8s) | Pi Zero 2 W only has 512MB RAM |
| CNI | Flannel (K3s default) | Calico, Weave | Simplicity; Cilium planned for Phase 2 |
| Ingress | Traefik v3 (K3s built-in) | ingress-nginx | ingress-nginx officially retired March 2026 |
| GitOps | ArgoCD | Flux | Familiarity; UI visibility useful for homelab |
| Secrets | SOPS + age | Bitnami Sealed Secrets, ESO | No external backend needed; simple file encryption; no Bitnami dependency |
| Metrics | metrics-server (K3s built-in) | kube-prometheus-stack | Stack too heavy for this hardware; `kubectl top` is sufficient |
| Load balancer | MetalLB (Layer 2) | Cloud LB | Bare-metal; Layer 2 ARP works on home LAN |
| Storage | local-path (K3s default) | Longhorn | Longhorn too heavy; revisit if persistent storage needs grow |
