#!/usr/bin/env bash
# Enable IPv4 forwarding and configure outbound SNAT (MASQUERADE) on a Linux BGP NVA
# while preserving original source IPs for RFC 1918 east-west traffic.
set -euo pipefail

echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-nva-ipforward.conf > /dev/null
sudo sysctl --system

sudo iptables -t nat -A POSTROUTING -d 10.0.0.0/8 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -d 172.16.0.0/12 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -d 192.168.0.0/16 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

cat /proc/sys/net/ipv4/ip_forward

