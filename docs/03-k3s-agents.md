# 03 — K3s Agents (Pi Zero 2 W Workers)

Repeat these steps for each node: p1, p2, p3, p4.

## Prerequisites

- K3s server is running on the Pi 4 controller
- You have the node token: `sudo cat /var/lib/rancher/k3s/server/node-token`
- Nodes are reachable: `ping 172.19.181.1` (run `clusterctrl hub on` first if unreachable)

## Step 1 — Enable cgroup memory

SSH into the node from the controller:
```bash
ssh warl0ck@172.19.181.1   # p1 — adjust IP for each node
```

Edit cmdline.txt and append to the **end of the existing single line**:
```bash
sudo nano /boot/firmware/cmdline.txt
# append: cgroup_memory=1 cgroup_enable=memory
sudo reboot
```

SSH back in after reboot before continuing.

## Step 2 — Install K3s agent

Download the script locally first (piping via `curl | bash` breaks interactive prompts):
```bash
curl -sfL https://raw.githubusercontent.com/TuckerWarlock/raspi-k3s-cluster/main/scripts/install-k3s-agent.sh -o install-k3s-agent.sh
```

Run it, passing the token and this node's IP:
```bash
K3S_TOKEN=<node-token> NODE_IP=172.19.181.1 bash install-k3s-agent.sh
# p1 → NODE_IP=172.19.181.1
# p2 → NODE_IP=172.19.181.2
# p3 → NODE_IP=172.19.181.3
# p4 → NODE_IP=172.19.181.4
```

## Step 3 — Verify (from Pi 4 controller)

```bash
kubectl get nodes -o wide
```

All four Pi Zeros should appear with status `Ready` within ~60 seconds of the agent starting.

## Label Nodes

```bash
kubectl label node p1 p2 p3 p4 node-role.kubernetes.io/worker=worker
kubectl label node p1 p2 p3 p4 hardware=pi-zero-2w
```

## Resource Limits Note

Pi Zero 2 W has 512MB RAM. Avoid scheduling memory-hungry pods here.
Use node selectors or taints to keep system workloads on the Pi 4:

```bash
kubectl taint node p1 p2 p3 p4 hardware=pi-zero-2w:NoSchedule
```

