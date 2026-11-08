# 02 — K3s Server (Pi 4 Control Plane)

> Reference guide. The ordered build steps (cgroups, install, kubeconfig) are in
> [rebuild.md](rebuild.md#phase-1--pi-4-controller), steps 1.2, 1.6, and 1.7.

## What `install-k3s-server.sh` configures

| Flag | Why |
|---|---|
| `--write-kubeconfig-mode 644` | `kubectl` on the Pi works without `sudo` |
| `--disable traefik` | Traefik is deployed by ArgoCD from its Helm chart instead ([05-traefik.md](05-traefik.md)) |
| `--disable servicelb` | K3s's built-in load balancer (klipper) conflicts with MetalLB |
| `--kubelet-arg=system-reserved=cpu=250m,memory=512Mi` | Keeps 512Mi for the OS, never allocatable to pods |
| `--kubelet-arg=eviction-soft=memory.available<512Mi,…` | Gracefully evicts pods after 2 minutes of memory pressure |
| `--kubelet-arg=eviction-hard=memory.available<300Mi,…` | Force-evicts before the kernel OOM killer can corrupt the SD card |
| `--kubelet-arg=eviction-max-pod-grace-period=90` | Evicted pods get up to 90s to shut down |

The eviction rationale (and why `eviction-hard` re-lists every default threshold) is in
[memory-management.md](memory-management.md#layer-2--kubelet-eviction-thresholds).

The script refuses to run unless `cgroup_memory=1 cgroup_enable=memory` is in
`/boot/firmware/cmdline.txt`. That file must stay **a single line** — a second line stops
the Pi from booting.

K3s runs single-server with SQLite (not etcd), which is far less write-heavy on the SD card.
The nightly `k3s-backup.timer` copies that SQLite datastore, the token, and the certs to the
USB drive ([rebuild.md step 1.8](rebuild.md#18--optional-restore-k3s-state-from-backup)).

## Troubleshooting

**`x509: certificate signed by unknown authority` from your laptop**

K3s regenerated its certificates (every fresh install does). Refresh the kubeconfig —
[rebuild.md step 1.7](rebuild.md#17--kubeconfig-on-your-laptop).

**K3s won't start after a reboot**

Usually the USB containerd bind mount is missing —
[rebuild.md → K3s won't start after a reboot](rebuild.md#k3s-wont-start-after-a-reboot).
Otherwise check the logs:

```bash
sudo systemctl status k3s
sudo journalctl -u k3s -n 100 --no-pager
```

**Node token** (needed by the agents): `sudo cat /var/lib/rancher/k3s/server/node-token`
