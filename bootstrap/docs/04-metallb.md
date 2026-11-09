# 04 — MetalLB (Bare-Metal Load Balancer)

> Reference guide. MetalLB is deployed by ArgoCD — there is no manual install step.
> See [rebuild.md step 3.4](rebuild.md#34--apply-the-root-application).

MetalLB gives the cluster real `LoadBalancer` services on bare metal using Layer 2 ARP.
Traefik is the only `LoadBalancer` service today; it gets `192.168.1.241`.

## How it's deployed

| ArgoCD app | Source | Deploys |
|---|---|---|
| `metallb` | `cluster/argocd/addons/metallb.yaml` (Helm chart + `cluster/core-system/metallb/values.yaml`) | Controller + speaker |
| `metallb-config` | `cluster/core-system/metallb/config/` | `IPAddressPool` + `L2Advertisement` |

`metallb-config` retries with backoff (up to 5 minutes) because its resources need the CRDs
that the `metallb` chart installs first. A few failed attempts right after bootstrap are
expected.

K3s's own load balancer (ServiceLB/klipper) conflicts with MetalLB; `install-k3s-server.sh`
disables it with `--disable servicelb`.

## Pool and placement

- **Pool:** `192.168.1.241`–`192.168.1.254` — outside the router's DHCP range (`.2`–`.240`).
- **Speaker and controller:** both pinned to `pi4controller`. L2 advertisement needs the LAN
  (`eth0`), and the Pi Zeros have no LAN interface.
- **FRR disabled** (`speaker.frr.enabled: false`): FRR is only used for BGP, and this cluster
  announces via L2 only. Re-enable it if you ever add a `BGPPeer`.

## Verify

```bash
kubectl -n metallb-system get pods -o wide             # controller 1/1, speaker 1/1 on pi4controller
kubectl -n metallb-system get ipaddresspool,l2advertisement
kubectl get svc -A | grep LoadBalancer                 # EXTERNAL-IP in .241–.254
```

## Troubleshooting

**Service stuck at `<pending>`**

```bash
kubectl -n argocd get app metallb metallb-config      # both Synced + Healthy?
kubectl -n metallb-system logs -l app.kubernetes.io/component=controller
```

If `metallb-config` gave up retrying, trigger it again:
`kubectl -n argocd annotate app metallb-config argocd.argoproj.io/refresh=hard --overwrite`.

**`metallb` app shows `Unknown` with `field not declared in schema`**

ArgoCD is older than the cluster's Kubernetes version and can't diff newer fields. Upgrade
the ArgoCD chart — see [07-argocd.md](07-argocd.md#troubleshooting).
