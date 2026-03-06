# 01 — ClusterHAT OS & CNAT Setup

Reference guides:
- https://clusterctrl.com/setup-control
- https://clusterctrl.com/setup-software

## Image Selection

Flash the correct ClusterHAT images for your hardware. Two variants are available depending on whether you want a desktop environment on the Pi 4 controller.

### Option A — Lite (headless, recommended for a cluster)

| Device | Image |
|--------|-------|
| Raspberry Pi 4 (controller) | **CNAT - Lite Controller** — Lite Bookworm image for the controller (3/3+/4/400) |
| p1 (Pi Zero 2 W) | **CNAT - Lite Bookworm** — Lite Bookworm image (Zero 2/A3+/CM3/CM4 only) P1 |
| p2 (Pi Zero 2 W) | **CNAT - Lite Bookworm** — Lite Bookworm image (Zero 2/A3+/CM3/CM4 only) P2 |
| p3 (Pi Zero 2 W) | **CNAT - Lite Bookworm** — Lite Bookworm image (Zero 2/A3+/CM3/CM4 only) P3 |
| p4 (Pi Zero 2 W) | **CNAT - Lite Bookworm** — Lite Bookworm image (Zero 2/A3+/CM3/CM4 only) P4 |

### Option B — Desktop (if you want a GUI on the Pi 4 controller)

| Device | Image |
|--------|-------|
| Raspberry Pi 4 (controller) | **CNAT - Desktop Controller** — Desktop Bookworm image for the controller (3/3+/4/400) |
| p1–p4 (Pi Zero 2 W) | Same Lite node images as above |

> Each Pi Zero node image is unique (P1/P2/P3/P4) — flash the correct one to each card.

## Flashing

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or `dd`/`balenaEtcher`.
Flash the controller image to the Pi 4's SD card, and each node image to its respective Pi Zero SD card.

## First Boot

1. Insert all SD cards, attach the ClusterHAT to the Pi 4, and power on the Pi 4.
2. The ClusterHAT controls power to p1–p4.
3. SSH into the Pi 4 controller:
   ```bash
   ssh pi@<pi4-ip>
   ```

## Power On the Nodes

```bash
clusterctrl on        # power on all nodes (p1–p4)
clusterctrl on p1     # power on a single node
clusterctrl status    # check node power status
```

## Enable CNAT

CNAT routes internet traffic from p1–p4 through the Pi 4 controller.

```bash
# On the Pi 4 controller
clusterctrl cnat on
```

Verify IP forwarding is active:

```bash
sysctl net.ipv4.ip_forward
# Expected: net.ipv4.ip_forward = 1
```

If not set, enable it permanently:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl -p /etc/sysctl.d/99-k3s.conf
```

## Verify Node Connectivity

SSH into each node from the Pi 4 and confirm internet access:

```bash
ssh pi@172.19.181.2   # p1
ssh pi@172.19.181.3   # p2
ssh pi@172.19.181.4   # p3
ssh pi@172.19.181.5   # p4

ping -c 3 8.8.8.8
```

> Default CNAT subnet is `172.19.181.x`. Verify with `ip addr` on the Pi 4's `usb0` interface.
