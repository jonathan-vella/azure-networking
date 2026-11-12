# BIRD BGP Daemon — Installation & Verification Notes

Quick operational reference for installing the **BIRD Internet Routing Daemon** on an Ubuntu Linux Network Virtual Appliance (NVA) and verifying eBGP sessions with **Azure Route Server** (`ASN 65515`) and a cross-region VXLAN peer.

## 1. Install & Start BIRD

```bash
sudo apt-get update
sudo apt-get install -y bird
sudo cp bird-east.conf /etc/bird/bird.conf
sudo systemctl restart bird.service
sudo systemctl status bird.service
```

## 2. Verify BGP Peerings in `birdc`

```text
root@bird-nva-east:~# birdc
BIRD ready.
bird> show protocols
name          proto    table    state  since       info
kernel1       Kernel   master   up     12:09:09
static1       Static   master   up     12:09:09
device1       Device   master   up     12:09:09
vxlan         BGP      master   up     12:09:14    Established
routeserver1  BGP      master   up     12:09:11    Established
routeserver2  BGP      master   up     12:09:13    Established
```

## 3. Useful Diagnostic Commands

```bash
# Show routes learned from Azure Route Server
sudo birdc 'show route protocol routeserver1'

# Show routes advertised to Azure Route Server
sudo birdc 'show route export routeserver1'

# Inspect Linux kernel routing table programmed by BIRD
ip route show
```
