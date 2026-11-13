#!/usr/bin/env bash
# Enable IPv4 forwarding and configure idempotent outbound SNAT (MASQUERADE) on
# a Linux BGP NVA while preserving original source IPs for RFC 1918 east-west traffic.
set -euo pipefail

DEFAULT_IF="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}' || true)"
WAN_IF="${WAN_IF:-${DEFAULT_IF:-eth0}}"

echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-nva-ipforward.conf > /dev/null
sudo sysctl --system > /dev/null

ensure_postrouting_rule() {
  sudo iptables -t nat -C POSTROUTING "$@" 2>/dev/null || sudo iptables -t nat -A POSTROUTING "$@"
}

ensure_postrouting_rule -d 10.0.0.0/8 -j ACCEPT
ensure_postrouting_rule -d 172.16.0.0/12 -j ACCEPT
ensure_postrouting_rule -d 192.168.0.0/16 -j ACCEPT
ensure_postrouting_rule -o "$WAN_IF" -j MASQUERADE

echo "IPv4 forwarding: $(cat /proc/sys/net/ipv4/ip_forward) (WAN_IF=${WAN_IF})"

