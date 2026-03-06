# 05 — Ingress Controller (Traefik)

K3s ships with Traefik. If you disabled it at install time, deploy it via Helm.

## Option A — Re-enable K3s built-in Traefik

Remove `--disable traefik` from your K3s server args and restart:

```bash
sudo systemctl restart k3s
```

## Option B — Install Traefik via Helm (more control)

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace
```

## Verify

```bash
kubectl get svc -n traefik
# Should show an EXTERNAL-IP from MetalLB
```

## Example Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
    - host: example.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: example-svc
                port:
                  number: 80
```
