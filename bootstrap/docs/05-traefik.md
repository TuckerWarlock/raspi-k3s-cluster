# 05 — Traefik (Ingress Controller)

> Reference guide. Traefik is deployed by ArgoCD — there is no manual install step.
> See [rebuild.md step 3.4](rebuild.md#34--apply-the-root-application) for bootstrap, 3.5 for
> the TLS secret, and 3.6 for hostnames.

Traefik is the single entry point for HTTP/HTTPS traffic. It gets `192.168.1.241` from
MetalLB and routes each request to a Service by its `Host` header.

## How it's deployed

- **ArgoCD app:** `cluster/argocd/addons/traefik.yaml` — Traefik Helm chart 42.x with values
  from `cluster/core-system/traefik/values.yaml`.
- **Why not K3s's bundled Traefik:** it's disabled (`--disable traefik`) so the chart version
  and values are pinned in Git.
- **`ServerSideApply=true`:** Traefik's CRDs are too large for ArgoCD's client-side diff;
  without it they stay `OutOfSync` and `selfHeal` re-syncs them on every reconcile.
- **Chart 42+:** no longer bundles Gateway API CRDs. K3s ships its own (v1.6+) and an
  admission policy that rejects older copies — which is what broke chart 39.

## Configuration

| Setting | Value |
|---|---|
| Placement | `pi4controller` (needs the MetalLB LAN IP) |
| Resources | 64Mi request / 128Mi limit |
| Entrypoints | `web` :80, `websecure` :443 (TLS) |
| Default TLS cert | Secret `cluster-local-tls` — mkcert wildcard for `*.cluster.local` ([rebuild.md 3.5](rebuild.md#35--create-the-tls-secret-for-clusterlocal)) |
| Access log | on |

Ingresses use `ingressClassName: traefik` and the annotation
`traefik.ingress.kubernetes.io/router.entrypoints: web,websecure`.

## Hostnames

| Host | Service |
|---|---|
| `argocd.cluster.local` | ArgoCD UI |
| `vm.cluster.local` | VictoriaMetrics (UI at `/vmui`) |
| `status.cluster.local` | Gatus |
| `traefik.cluster.local` | Traefik dashboard at `/dashboard/` |
| `ntfy.home.arpa` | ntfy — not `.local`, because iOS won't resolve `.local` through DNS. Uses its own mkcert cert (`ntfy-tls` in the `ntfy` namespace) |

All point to `192.168.1.241` — via Pi-hole Local DNS records or `/etc/hosts`
([rebuild.md 3.6](rebuild.md#36--resolve-the-hostnames)).

The dashboard route is scoped to `Host(traefik.cluster.local)`. The chart default matches
`/dashboard` and `/api` on **every** host, which captured other apps' `/api/*` paths over
HTTP (VictoriaMetrics, Gatus) and returned 404.

## Verify

```bash
kubectl -n traefik get pods,svc            # 1/1 Running; EXTERNAL-IP 192.168.1.241
curl -sI http://192.168.1.241              # 404 = Traefik is up, no route for a bare IP
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: traefik.cluster.local" http://192.168.1.241/dashboard/   # 200
```

## Troubleshooting

**`EXTERNAL-IP` stays `<pending>`** — MetalLB has no pool yet; see
[04-metallb.md](04-metallb.md#troubleshooting).

**Browser shows a certificate warning** — the `cluster-local-tls` secret is missing
(`kubectl -n traefik get secret cluster-local-tls`), or this device doesn't trust the mkcert CA.

**Hostname returns 404**

```bash
kubectl get ingress -A                      # is the Ingress there, with the right host?
kubectl -n traefik logs deploy/traefik --tail=50
```

Check `ingressClassName: traefik` is set, and that the path isn't `/api/*` on the `web`
entrypoint being captured by another route.
