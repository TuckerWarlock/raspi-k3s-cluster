# Step 04: MetalLB (Bare-Metal Load Balancer)

## Overview

MetalLB gives your cluster real `LoadBalancer` type services on bare metal using Layer 2 ARP (address resolution protocol).

| Component | Scope | Storage | Memory |
|-----------|-------|---------|--------|
| MetalLB speakers | DaemonSet pinned to pi4controller | N/A | ~70MB total |
| IPAddressPool | Cluster config | N/A | N/A |

## Prerequisites

- K3s cluster running (steps 01–03)

> **⚠️ K3s ships with a built-in load balancer called klipper (ServiceLB).** It conflicts with
> MetalLB and will prevent it from setting up iptables DNAT rules for LoadBalancer IPs.
> The `install-k3s-server.sh` script already passes `--disable servicelb` to handle this.

## Installation

MetalLB is deployed as part of the core infrastructure via helmfile:

```bash
helmfile sync
```

This installs the MetalLB controller and speaker DaemonSet (pinned to pi4controller only —
Pi Zeros have no LAN interface for L2 advertisement).

After `helmfile sync`, the `IPAddressPool` and `L2Advertisement` CRDs must be applied
separately — they are raw manifests, not part of the Helm chart:

```bash
kubectl apply -f cluster/core-system/metallb/ipaddresspool.yaml
kubectl apply -f cluster/core-system/metallb/l2advertisement.yaml
```

The IP pool is pre-configured to use `192.168.1.241–192.168.1.254` (outside the router's DHCP range).

## Verify

```bash
kubectl -n metallb-system get pods
# Should show: controller-xxxxx (1 replica), speaker-xxxxx (1 replica on pi4controller)

kubectl -n metallb-system get ipaddresspool
kubectl -n metallb-system get l2advertisement
```

## Testing

Deploy a test LoadBalancer service:

```bash
kubectl create service loadbalancer test-lb --tcp=8080:8080 --dry-run=client -o yaml | \
  kubectl set env -f - SOME_VAR=test -o yaml | kubectl apply -f -
```

Or check existing services:

```bash
kubectl get svc -A | grep LoadBalancer
```

Any service with `type: LoadBalancer` should get an EXTERNAL-IP from the pool (192.168.1.241–254).
