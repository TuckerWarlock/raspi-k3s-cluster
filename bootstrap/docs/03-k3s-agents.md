# 03 — K3s Agents (Pi Zero 2 W Workers)

> Reference guide. The ordered build steps are in
> [rebuild.md](rebuild.md#phase-2--pi-zero-workers), Phase 2.

## Why underclock

The Pi Zero 2 W draws much more power than the original Pi Zero, and all four are powered
from the Pi 4 through the ClusterHAT. At stock clocks, booting the nodes browns out the Pi 4
and drops its network. The `config.txt` lines in rebuild step 2.1 cap the CPU at 600MHz,
give the GPU the minimum 16MB, and turn off WiFi and Bluetooth. The Zeros reach the network
only through the USB CNAT link (`172.19.181.x`), so WiFi isn't needed.

## What `install-k3s-agent.sh` configures

| Setting | Value | Why |
|---|---|---|
| Server | `https://172.19.181.254:6443` | The Pi 4's address on the CNAT bridge |
| `--node-ip` | `172.19.181.N` (`NODE_IP`) | The node's CNAT address, not a LAN one (it has none) |
| `--flannel-iface` | `usb0` | Pod traffic goes over the ClusterHAT USB link |

It takes `K3S_TOKEN` and `NODE_IP` from the environment (and prompts if they're missing —
which is why it must be downloaded, not piped from `curl`). Like the server script, it checks
for the memory cgroup flags first.

## Labels and scheduling

| Label | Used by |
|---|---|
| `node-role.kubernetes.io/worker=worker` | ArgoCD server, redis, and repo-server (`nodeSelector` in `cluster/argocd/argocd-values.yaml`) |
| `hardware=pi-zero-2w` | Available for hardware-aware scheduling; nothing requires it today |

**Don't taint the Zeros.** The ArgoCD components above have no toleration, so a
`NoSchedule` taint would leave them unschedulable. Placement rules for new workloads:
[architecture.md → Workload Placement](architecture.md#workload-placement).

Each Zero has 512MB RAM — the K3s agent minimum — and idles around 200–250Mi. Keep anything
scheduled here small.

## Troubleshooting

- **Node unreachable** (`Could not resolve hostname pN.local`, no `ethpiN` interface) —
  [rebuild.md → Pi Zero unreachable](rebuild.md#pi-zero-unreachable).
- **Agents `NotReady` after the controller was rebuilt** (new token and CA) —
  [rebuild.md → agents NotReady](rebuild.md#pi-zero-agents-notready-after-a-controller-rebuild).
- **Agent logs** (on the node): `sudo journalctl -u k3s-agent -n 100 --no-pager`
