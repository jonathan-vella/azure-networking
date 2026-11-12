# VXLAN Overlay Tunnel Between Cross-Region Linux NVAs

Azure Virtual Networks do not forward raw L2 multicast or arbitrary spoofed inner MAC frames natively, so overlay protocols between Linux NVAs (or BGP speakers testing transitive routing across regions) use **unicast VXLAN** (`dstport 4789`) over routed VNet peering.

---

## Region East (`bird-nva-east` — `172.16.25.4/24`)

```bash
# Inspect underlay NIC (eth0: 172.16.25.4/24, Azure subnet gateway: 172.16.25.1)
ip addr show dev eth0

# Ensure /32 underlay reachability to the West NVA via Azure's subnet gateway (.1)
sudo ip route replace 172.17.25.4/32 via 172.16.25.1 dev eth0

# Create VXLAN interface (VNI 5001, standard IANA UDP port 4789)
sudo ip link add vxlan-demo type vxlan id 5001 \
  remote 172.17.25.4 \
  local 172.16.25.4 \
  dev eth0 \
  dstport 4789

sudo ip addr add 192.168.100.1/24 dev vxlan-demo
sudo ip link set up dev vxlan-demo

# Enable IPv4 packet forwarding in the Linux kernel (also enable IP Forwarding on the Azure NIC!)
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-nva-ipforward.conf
sudo sysctl --system
```

---

## Region West (`bird-nva-west` — `172.17.25.4/24`)

```bash
# Inspect underlay NIC (eth0: 172.17.25.4/24, Azure subnet gateway: 172.17.25.1)
ip addr show dev eth0

# Ensure /32 underlay reachability to the East NVA via Azure's subnet gateway (.1)
sudo ip route replace 172.16.25.4/32 via 172.17.25.1 dev eth0

# Create matching VXLAN interface (VNI 5001, UDP 4789)
sudo ip link add vxlan-demo type vxlan id 5001 \
  remote 172.16.25.4 \
  local 172.17.25.4 \
  dev eth0 \
  dstport 4789

sudo ip addr add 192.168.100.2/24 dev vxlan-demo
sudo ip link set up dev vxlan-demo

# Enable IPv4 packet forwarding
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-nva-ipforward.conf
sudo sysctl --system
```

---

## MTU & Azure NIC Checklist

1. **Azure NIC IP Forwarding**: Enable `enableIPForwarding: true` on both Azure Network Interfaces (`eth0`).
2. **NSG Rules**: Allow UDP `4789` (VXLAN underlay) and TCP `179` (BGP over VXLAN + BGP to `RouteServerSubnet`).
3. **Inner MTU**: VXLAN adds 50 bytes of encapsulation overhead; clamping inner interface MTU to `1450` (`sudo ip link set dev vxlan-demo mtu 1450`) prevents fragmentation over Azure's 1500-byte VNet MTU.
