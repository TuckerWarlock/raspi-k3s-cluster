# clusterctrl — Command Reference

`clusterctrl` is pre-installed on the ClusterHAT controller image and is the primary tool
for managing node power, the USB hub, LEDs, and fan.

## Node Power

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

## USB Hub

```bash
clusterctrl hub on
clusterctrl hub off
```

## Alert LED

```bash
clusterctrl led on
clusterctrl led off
```

## Fan (ClusterHAT Case — e.g. PiHut case)

The fan is controlled via GPIO 18. Before using `clusterctrl fan`, you must first
configure GPIO 18 as an output. Add this to `/etc/rc.local` (before `exit 0`) so it
persists across reboots:

```bash
raspi-gpio set 18 op pn dh
```

Then control the fan:

```bash
clusterctrl fan on
clusterctrl fan off
```

> **Note:** Without running `raspi-gpio set 18 op pn dh` first, `clusterctrl fan` won't work.
> The PiHut ClusterHAT case fan is wired to GPIO 18.

### Make Fan Setup Persistent

```bash
sudo nano /etc/rc.local
```

Add before `exit 0`:
```bash
raspi-gpio set 18 op pn dh
```

Or create a systemd service to be more explicit:

```bash
sudo tee /etc/systemd/system/clusterhat-fan.service > /dev/null <<EOF
[Unit]
Description=Enable ClusterHAT fan GPIO
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/raspi-gpio set 18 op pn dh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now clusterhat-fan.service
```

## Typical Boot Sequence

After the Pi 4 controller boots, run these to bring the cluster fully online:

```bash
raspi-gpio set 18 op pn dh   # enable fan GPIO (if not in rc.local/systemd yet)
clusterctrl fan on            # start the fan
clusterctrl on                # power on p1–p4
clusterctrl status            # verify all nodes are on
```

Then wait ~60 seconds for the Pi Zeros to finish booting before proceeding with K3s setup.

## SSH Into Nodes

The node hostnames default to `p1`–`p4` on the CNAT subnet:

```bash
ssh pi@p1   # or ssh pi@172.19.181.1
ssh pi@p2
ssh pi@p3
ssh pi@p4
```

> Tip: Add the Pi 4's CNAT interface IP and node hostnames to `/etc/hosts` on the Pi 4
> if DNS resolution isn't working for the node shortnames.
