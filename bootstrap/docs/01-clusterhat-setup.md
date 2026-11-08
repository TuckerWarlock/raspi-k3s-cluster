# 01 — ClusterHAT OS Setup & Management

> Reference guide. The ordered build steps are in [rebuild.md](rebuild.md).

Reference: https://clusterctrl.com/setup-control and https://clusterctrl.com/setup-software

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

Raspberry Pi Imager **v2.0 and newer breaks the "Customize" option** for third-party images like the ClusterHAT images. The OS Customization dialog (where you set WiFi, SSH, and username/password) will not appear or will be greyed out for these images in newer versions.

**Download v1.9.6 specifically:** 👉 https://github.com/raspberrypi/rpi-imager/releases/tag/v1.9.6

With v1.9.6, after selecting your image and target SD card, click **"Edit Settings"** (the gear/customize button) to configure:

- ✅ **Hostname** — set unique names (e.g. `controller`, `p1`, `p2`, `p3`, `p4`)
- ✅ **SSH** — enable SSH (use password authentication)
- ✅ **Username / Password** — set your `pi` user password
- ❌ **WiFi SSID / Password** — **leave blank on all images** — use ethernet only on the Pi 4 controller. WiFi causes instability and makes the Pi harder to recover if it goes offline. Pi Zero nodes connect via USB through the HAT, not WiFi.
- ✅ **Locale / Timezone** — optional but saves time

> The Pi Zero node images (p1–p4) do **not** need WiFi configured — they reach the network through the ClusterHAT USB connection to the Pi 4. Still set SSH, username, and password on each.

Flash the controller image to the Pi 4's SD card, then flash each node image (P1/P2/P3/P4) to its respective Pi Zero SD card with the appropriate hostname.

## First Boot

1. Insert all SD cards, attach the ClusterHAT to the Pi 4, and power on the Pi 4.
2. The ClusterHAT controls power to p1–p4.
3. SSH into the Pi 4 controller:
   ```bash
   ssh warl0ck@pi4controller.local   # the username you set in Imager
   ```

## Power Management with clusterctrl

`clusterctrl` is pre-installed on the ClusterHAT controller image and is the primary tool for managing node power, the USB hub, LEDs, and fan.

### Node Power

```bash
# Power on all nodes (p1–p4)
clusterctrl on

# Power off all nodes
clusterctrl off

# Power on/off individual nodes
clusterctrl on p1
clusterctrl off p3
clusterctrl on p1 p2 p3 p4   # multiple at once

# Check power status of all nodes
clusterctrl status
```

### USB Hub

```bash
clusterctrl hub on
clusterctrl hub off
```

### Alert LED

```bash
clusterctrl led on
clusterctrl led off
```

### Fan (ClusterHAT Case — e.g. PiHut case)

The fan is on GPIO 18, which must be set as an output before `clusterctrl fan` works.
On Bookworm use `pinctrl` (`raspi-gpio` is deprecated):

```bash
pinctrl set 18 op pn dh
clusterctrl fan on     # or: clusterctrl fan off
```

`setup-controller.sh` installs `clusterhat-fan.service`, which runs both commands on every boot,
so there's nothing to add to `/etc/rc.local`. Check it with `systemctl status clusterhat-fan`.

## ⚠️ Critical Hardware & Power Notes

### Shutdown Order — MANDATORY

**Always power off Pi Zero nodes BEFORE rebooting or shutting down the Pi 4.**

If the Pi 4 loses power while nodes are running, they will still be drawing current from the GPIO 5V rail. On the next Pi 4 boot, all nodes will immediately spike power demand before the Pi 4 can establish network — causing a brownout loop that prevents the controller from ever coming back online.

```bash
# Always run this before sudo reboot or unplugging the Pi 4:
clusterctrl off
sudo shutdown -h now   # or sudo reboot
```

**If you're already stuck in a brownout loop:**
1. Unplug the Pi 4
2. Remove all 4 Pi Zero SD cards (underside of ClusterHAT)
3. Power on the Pi 4 alone — nodes won't boot, no power spike
4. SSH in, then reinsert SD cards one at a time with 30s delays

### Node Boot Power Spikes

**Power on nodes one at a time with 30s delays.** Pi Zero 2 W nodes draw significantly more power than original Pi Zeros. Powering them all on simultaneously causes boot power spikes that can brownout the Pi 4 and drop its network connectivity. The commands are in [Typical Boot Sequence](#typical-boot-sequence) below.

### Power Wiring — Critical

The ClusterHAT's micro-USB power port **must be connected to a blue USB 3.0 port** on the Pi 4 (or an independent USB power supply). The black USB 2.0 ports only supply 500mA — not enough for the HAT + Pi Zero 2 W nodes, causing the Pi 4 to brown out and drop its network connection whenever a node powers on.

| Port color | Standard | Max current | Works? |
|------------|----------|-------------|--------|
| Black      | USB 2.0  | 500 mA      | ❌ Too low — causes brownouts |
| Blue       | USB 3.0  | 900 mA      | ✅ Required |

> **Symptom of wrong port:** Pi 4 SSH drops immediately after `clusterctrl on p1` — even with a single node. Moving the micro-USB cable to a blue port fixes it.

## Typical Boot Sequence

After the Pi 4 controller boots, run these to bring the cluster fully online:

```bash
# Fan starts automatically via clusterhat-fan.service (setup-controller.sh)
clusterctrl hub on            # enable the USB hub (required for node connectivity)

# Power on nodes ONE AT A TIME with 30s delays — prevents boot power spikes
for i in 1 2 3 4; do
  echo "==> Powering on p$i..."
  clusterctrl on p$i
  sleep 30
done

clusterctrl status            # verify all nodes are on
```

> **Note:** `clusterctrl hub on` must be run after every controller reboot before the nodes are reachable. Without it, pings and SSH to `172.19.181.x` will return "Destination Host Unreachable" even if the nodes are powered on.

Then wait ~60 seconds for the Pi Zeros to finish booting before proceeding with K3s setup.

## CNAT (Network Routing)

The CNAT controller image already routes p1–p4's traffic through the Pi 4 — there is nothing
to enable (`clusterctrl cnat on` is not a valid command on this image). Check that forwarding
is on:

```bash
sysctl net.ipv4.ip_forward   # Expected: net.ipv4.ip_forward = 1
```

If it isn't:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl -p /etc/sysctl.d/99-k3s.conf
```

## Verify Node Connectivity

From the Pi 4, SSH into each node and confirm internet access:

```bash
ssh warl0ck@172.19.181.1   # p1 — .2/.3/.4 for p2–p4 (or p1.local etc. once mDNS resolves)
ping -c 3 8.8.8.8          # from within the node
```

> The CNAT subnet is `172.19.181.0/24`: the Pi 4 is `.254` on `br0`, and each node appears
> on the Pi 4 as an `ethpiN` interface. A node that's powered on but has no `ethpiN` needs
> a power cycle — see [rebuild.md → Pi Zero unreachable](rebuild.md#pi-zero-unreachable).
