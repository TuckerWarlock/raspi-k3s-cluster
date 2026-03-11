# 05 — Ingress Controller (Traefik)

K3s ships with a built-in Traefik, but we disable it at install time (`--disable traefik`)
and install via Helm for full control over configuration.

## Install via Helm

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
