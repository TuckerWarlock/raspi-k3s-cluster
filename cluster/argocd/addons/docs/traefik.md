# Step 05: Ingress Controller (Traefik)

## Overview

K3s ships with Traefik by default, but we disable it at install time (`--disable traefik`) and deploy via Helm for full control over configuration.

| Component | Deployment | Storage | Memory |
|-----------|-----------|---------|--------|
| Traefik controller | Deployment on pi4controller | N/A | ~45MB |
| Traefik Service | LoadBalancer (gets IP from MetalLB) | N/A | N/A |

## Prerequisites

- K3s cluster running (steps 01–03)
- MetalLB configured (step 04)

## Installation

Traefik is deployed as part of the core infrastructure via helmfile:

```bash
helmfile sync
```

This installs:
- Traefik controller Deployment on pi4controller
- Traefik Service of type `LoadBalancer` (gets EXTERNAL-IP from MetalLB pool)
- Helm values from `cluster/core-system/traefik/values.yaml`

## Verify

```bash
kubectl -n traefik get pods
# Should show: traefik-xxxxx (1 replica)

kubectl -n traefik get svc
# Should show EXTERNAL-IP from MetalLB pool (192.168.1.241–254)
```

## Testing

Create a simple test Ingress:

```bash
kubectl apply -f cluster/core-system/traefik/traefik-test-ingress.yaml
```

Verify it was created:

```bash
kubectl get ingress -A
```

The test ingress should show an `HOSTS` column with `traefik-test.cluster.local`.

Add to your laptop's `/etc/hosts` (replace with EXTERNAL-IP from traefik service above):

```
192.168.1.241 traefik-test.cluster.local
```

Then visit: http://traefik-test.cluster.local (you'll see the Traefik dashboard or a simple response).

## Example Ingress

To expose your own services via Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
    - host: my-app.cluster.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app-svc
                port:
                  number: 8080
```

Then add the hostname to your `/etc/hosts` and access it.
