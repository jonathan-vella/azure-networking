# BIRD 2 BGP daemon: installation and verification notes

Operational reference for installing **BIRD 2** (`bird2`) on an Ubuntu 24.04 LTS (`noble`) Linux Network Virtual Appliance (NVA) and verifying eBGP sessions with **Azure Route Server** (`ASN 65515`) and a cross-region VXLAN peer.

> **BIRD 2 syntax note:** Ubuntu 24.04 LTS ships `bird2` (`/etc/bird/bird.conf`) and removed the legacy `bird` 1.6 package. In BIRD 2, `protocol kernel`, `protocol static`, and `protocol bgp` require explicit `ipv4 { ... };` channel blocks, and the default IPv4 RIB is named `master4`.

## 1. Install, validate, and reload BIRD 2

```bash
sudo apt-get update
sudo apt-get install -y bird2
sudo cp bird-east.conf /etc/bird/bird.conf

# Parse and validate configuration syntax before reloading
sudo bird -p -c /etc/bird/bird.conf

# Enable service and apply configuration live without dropping existing sessions
sudo systemctl enable --now bird.service
sudo birdc configure
sudo systemctl status bird.service --no-pager
```

## 2. Verify BGP peerings in `birdc`

```text
root@bird-nva-east:~# sudo birdc show protocols
BIRD 2.14 ready.
Name          Proto      Table      State  Since         Info
device1       Device     ---        up     12:09:09.104
kernel1       Kernel     master4    up     12:09:09.104
static1       Static     master4    up     12:09:09.104
vxlan         BGP        ---        up     12:09:14.220  Established
routeserver1  BGP        ---        up     12:09:11.512  Established
routeserver2  BGP        ---        up     12:09:13.008  Established
```

Inspect detailed per-channel `ipv4` import/export counters and hold timers:

```bash
sudo birdc show protocols all
sudo birdc show protocols all routeserver1
```

## 3. Diagnostic and live operations commands

```bash
# Re-read /etc/bird/bird.conf and apply changes non-disruptively
sudo birdc configure

# Show prefixes learned from Azure Route Server instance 1
sudo birdc 'show route protocol routeserver1'

# Show prefixes advertised to Azure Route Server after to_routeserver filtering
sudo birdc 'show route export routeserver1'

# Inspect the Linux kernel routing table programmed by BIRD 2
ip route show
```
