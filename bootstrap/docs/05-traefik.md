# 05 — Traefik (Ingress Controller)

Traefik acts as the single entry point for all HTTP/HTTPS traffic into the cluster. It
receives a `LoadBalancer` IP from MetalLB and routes requests to services based on `Ingress`
resources.

K3s ships with Traefik by default, but we disable the bundled version (`--disable traefik`)
and deploy via Helm for full configuration control.

## Prerequisites

- K3s server and agents running (steps 01–03)
- MetalLB installed and IP pool applied (step 04)

## Step 1 — Install Traefik via helmfile

If you ran `helmfile sync` in step 04, Traefik is already installed. Verify:

```bash
kubectl -n traefik get pods
kubectl -n traefik get svc
```

The `traefik` service should have an `EXTERNAL-IP` from the MetalLB pool
(e.g. `192.168.1.241`). If it shows `<pending>`, MetalLB's IP pool has not been applied —
go back to step 04.

If helmfile has not been run yet:

```bash
cd ~/raspi-k3s-cluster
helmfile sync
```

## Step 2 — Add cluster hostnames to /etc/hosts (laptop)

Traefik routes traffic based on the `Host` header. Add the Traefik external IP to
`/etc/hosts` on your laptop for each hostname you want to resolve:

```bash
# Replace 192.168.1.241 with your actual Traefik EXTERNAL-IP
echo "192.168.1.241 argocd.cluster.local" | sudo tee -a /etc/hosts
echo "192.168.1.241 prometheus.cluster.local" | sudo tee -a /etc/hosts
echo "192.168.1.241 grafana.cluster.local" | sudo tee -a /etc/hosts
```

> You only need to do this once per hostname. The same IP is used for all cluster services —
> Traefik routes them by `Host` header.

## Step 3 — Verify

```bash
kubectl -n traefik get pods
# Expected: traefik-xxxxx (1/1 Running)

kubectl -n traefik get svc
# Expected: traefik LoadBalancer <cluster-ip> 192.168.1.241 80:xxxxx/TCP,443:xxxxx/TCP

# Test HTTP reachability from laptop (replace IP with your Traefik EXTERNAL-IP)
curl -I http://192.168.1.241
# Expected: 404 (no default backend) — Traefik is up, just no matching route yet
```

## Traefik Dashboard

The dashboard is enabled on the `web` entrypoint (port 80) at `/dashboard/`:

```bash
# From laptop, after /etc/hosts is set or using the raw IP:
curl http://192.168.1.241/dashboard/
```

Or port-forward to avoid needing /etc/hosts:
```bash
kubectl port-forward -n traefik svc/traefik 9000:9000
# Open http://localhost:9000/dashboard/
```

## Troubleshooting

**EXTERNAL-IP stays `<pending>`**

MetalLB has not assigned an IP. Verify the pool is applied:
```bash
kubectl -n metallb-system get ipaddresspool
```
If missing, re-apply it (see step 04).

**curl returns `connection refused`**

Traefik pod may not be running:
```bash
kubectl -n traefik get pods
kubectl -n traefik logs -l app.kubernetes.io/name=traefik
```

**Ingress created but hostname returns 404**

Check Traefik has picked up the Ingress:
```bash
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>
```

Ensure `ingressClassName: traefik` is set on the Ingress resource.
