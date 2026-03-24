# 04 — MetalLB (Bare-Metal Load Balancer)

MetalLB gives your cluster real `LoadBalancer`-type services on bare metal using Layer 2
ARP. Every service with `type: LoadBalancer` (including Traefik) will receive an IP from the
pool you define here.

## Prerequisites

- K3s server and agents are running (steps 01–03)
- Helm and Helmfile are installed on the controller (`install-helm.sh`)

> **K3s ships with its own load balancer (klipper / ServiceLB).** It conflicts with MetalLB.
> `install-k3s-server.sh` already passes `--disable servicelb` to prevent this.

## Step 1 — Install MetalLB via helmfile

`helmfile sync` installs MetalLB (and the rest of the core stack — see steps 05–07).
If you haven't run it yet, do so now from the controller:

```bash
cd ~/raspi-k3s-cluster
helmfile sync
```

This deploys the MetalLB controller and speaker via Helm. At this point MetalLB is running
but has **no IP pool** — any `LoadBalancer` service will stay `<pending>`.

## Step 2 — Apply the IP address pool

The `IPAddressPool` and `L2Advertisement` are raw Kubernetes CRDs, not part of the Helm
chart. They must be applied separately after the MetalLB CRD webhook is ready:

```bash
kubectl apply -f cluster/core-system/metallb/ipaddresspool.yaml
kubectl apply -f cluster/core-system/metallb/l2advertisement.yaml
```

The pool is pre-configured for `192.168.1.241–192.168.1.254` — outside the router's DHCP
range (`.2–.240`). The L2Advertisement is pinned to `pi4controller` because the Pi Zeros
have no LAN interface and cannot participate in L2 advertisement.

## Step 3 — Verify

```bash
kubectl -n metallb-system get pods
# Expected: controller-xxxxx (1/1 Running), speaker-xxxxx (4/4 Running on pi4controller)

kubectl -n metallb-system get ipaddresspool,l2advertisement
# Expected: local-pool and local-advertisement both listed
```

Any `LoadBalancer` service should now receive an IP:

```bash
kubectl get svc -A | grep LoadBalancer
# EXTERNAL-IP should show an address in 192.168.1.241–254
```

## Troubleshooting

**Service stuck at `<pending>` after applying the pool**

Check MetalLB controller logs:
```bash
kubectl -n metallb-system logs -l app=metallb,component=controller
```

Common causes:
- Pool was applied before the MetalLB CRD webhook was ready — delete and re-apply:
  ```bash
  kubectl delete -f cluster/core-system/metallb/ipaddresspool.yaml
  kubectl delete -f cluster/core-system/metallb/l2advertisement.yaml
  kubectl apply -f cluster/core-system/metallb/ipaddresspool.yaml
  kubectl apply -f cluster/core-system/metallb/l2advertisement.yaml
  ```
- Speaker pod is not running on pi4controller — verify with `kubectl -n metallb-system get pods -o wide`

**Speaker pod not scheduled on pi4controller**

The `values.yaml` pins the speaker via `nodeSelector`. Verify the node is labelled correctly:
```bash
kubectl get node pi4controller --show-labels | grep hostname
```
