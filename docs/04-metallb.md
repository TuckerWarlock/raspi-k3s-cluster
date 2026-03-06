# 04 — MetalLB (Bare-Metal Load Balancer)

MetalLB gives your cluster real `LoadBalancer` type services on bare metal using Layer 2 ARP.

## Install via Helm

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
