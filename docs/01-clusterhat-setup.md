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

### ⚠️ Use Raspberry Pi Imager v1.9.6 — NOT the latest version

Raspberry Pi Imager **v2.0 and newer breaks the "Customize" option** for third-party images
like the ClusterHAT images. The OS Customization dialog (where you set WiFi, SSH, and
username/password) will not appear or will be greyed out for these images in newer versions.

**Download v1.9.6 specifically:**
👉 https://github.com/raspberrypi/rpi-imager/releases/tag/v1.9.6

With v1.9.6, after selecting your image and target SD card, click **"Edit Settings"**
(the gear/customize button) to configure:

- ✅ **Hostname** — set unique names (e.g. `controller`, `p1`, `p2`, `p3`, `p4`)
- ✅ **SSH** — enable SSH (use password authentication)
- ✅ **Username / Password** — set your `pi` user password
- ✅ **WiFi SSID / Password** — set on the Pi 4 controller image only (nodes connect via USB through the HAT, not WiFi)
- ✅ **Locale / Timezone** — optional but saves time

> The Pi Zero node images (p1–p4) do **not** need WiFi configured — they reach the network
> through the ClusterHAT USB connection to the Pi 4. Still set SSH, username, and password on each.

Flash the controller image to the Pi 4's SD card, then flash each node image (P1/P2/P3/P4)
to its respective Pi Zero SD card with the appropriate hostname.

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

See [01b-clusterctrl-reference.md](01b-clusterctrl-reference.md) for the full command reference including fan, hub, and LED control.

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
ssh pi@172.19.181.1   # p1
ssh pi@172.19.181.2   # p2
ssh pi@172.19.181.3   # p3
ssh pi@172.19.181.4   # p4

ping -c 3 8.8.8.8
```

> Default CNAT subnet is `172.19.181.x`. Verify with `ip addr` on the Pi 4's `usb0` interface.
