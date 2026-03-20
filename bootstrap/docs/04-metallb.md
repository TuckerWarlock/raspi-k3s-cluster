# 04 — MetalLB (Bare-Metal Load Balancer)

MetalLB gives your cluster real `LoadBalancer` type services on bare metal using Layer 2 ARP.

## Install via Helm

> **⚠️ K3s ships with a built-in load balancer called klipper (ServiceLB).** It conflicts with
> MetalLB and will prevent it from setting up iptables DNAT rules for LoadBalancer IPs.
> The `install-k3s-server.sh` script already passes `--disable servicelb` to handle this.
> If you installed K3s manually without that flag, MetalLB will silently fail to work.

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  --wait
```

## Configure IP Address Pool

Edit `manifests/metallb/ipaddresspool.yaml` with a range from your LAN subnet
that is **outside your router's DHCP range**:

```bash
kubectl apply -f manifests/metallb/ipaddresspool.yaml
kubectl apply -f manifests/metallb/l2advertisement.yaml
```

## Verify

```bash
kubectl get pods -n metallb-system
```

Deploy a test service with `type: LoadBalancer` and confirm it gets an EXTERNAL-IP from your pool:

```bash
kubectl get svc
```
