#!/usr/bin/env bash
# ==============================================================================
# Walkthrough: Linux Container Networking Fundamentals
#
# Run individual stages on docker-host-1 and docker-host-2 provisioned by
# build-docker-hosts.sh:
#   ./docker-networking-basics.sh basics
#   ./docker-networking-basics.sh bridge-host1
#   ./docker-networking-basics.sh bridge-host2
#   ./docker-networking-basics.sh dual-homed
#   ./docker-networking-basics.sh ipvlan-same-subnet
#   ./docker-networking-basics.sh ipvlan-routed
#   ./docker-networking-basics.sh cleanup
# ==============================================================================
set -euo pipefail

PREFIX="${PREFIX:-docker-net}"
LOCATION="${LOCATION:-eastus2}"
RG="${RG:-${PREFIX}-rg}"
DEFAULT_IF="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}' || true)"
PARENT_IF="${PARENT_IF:-${DEFAULT_IF:-eth0}}"
BRIDGE_NAME="${BRIDGE_NAME:-red-bridge}"
BRIDGE_SUBNET="${BRIDGE_SUBNET:-172.20.0.0/16}"
IPVLAN_NAME="${IPVLAN_NAME:-ipvlan-net}"
VNET_SUBNET="${VNET_SUBNET:-10.1.1.0/24}"

STAGE="${1:-help}"

run_basics() {
  docker version
  docker info
  ip addr show
  docker run --rm hello-world

  docker rm -f blue1 blue2 web-published web-random 2>/dev/null || true
  docker run -dit --name blue1 nginxdemos/hello
  docker run -dit --name blue2 nginxdemos/hello
  docker ps

  docker exec blue1 ip addr show
  docker exec blue1 ping -c 3 8.8.8.8
  docker exec blue1 sh -c 'wget -qO- http://ifconfig.me || true'
  echo ""

  # Publish container port 80 on host port 8080, and publish all exposed ports (-P)
  docker run -dit --name web-published -p 8080:80 nginxdemos/hello
  docker run -dit --name web-random -P nginxdemos/hello
  docker ps
}

run_bridge_host1() {
  brctl show || bridge link show
  docker network ls

  docker rm -f red1 red2 2>/dev/null || true
  docker network rm "$BRIDGE_NAME" 2>/dev/null || true
  docker network create --subnet "$BRIDGE_SUBNET" -d bridge "$BRIDGE_NAME"
  docker network ls

  docker run -dit --name red1 --network "$BRIDGE_NAME" --ip 172.20.1.10 nginxdemos/hello
  docker run -dit --name red2 --network "$BRIDGE_NAME" --ip 172.20.1.11 nginxdemos/hello
  docker network inspect bridge "$BRIDGE_NAME"
  docker ps

  # Same-host custom bridge: automatic DNS + L2 reachability succeeds
  docker exec red1 ip addr show
  docker exec red1 ping -c 3 red2

  # Cross-host isolated bridge: 172.20.1.12 on docker-host-2 is unreachable without overlay/routing
  docker exec red1 ping -c 2 -W 2 172.20.1.12 || echo "Expected failure: isolated bridge does not span VMs"
}

run_bridge_host2() {
  docker rm -f red3 red4 2>/dev/null || true
  docker network rm "$BRIDGE_NAME" 2>/dev/null || true
  docker network create --subnet "$BRIDGE_SUBNET" -d bridge "$BRIDGE_NAME"

  docker run -dit --name red3 --network "$BRIDGE_NAME" --ip 172.20.1.12 nginxdemos/hello
  docker run -dit --name red4 --network "$BRIDGE_NAME" --ip 172.20.1.13 nginxdemos/hello
  docker exec red3 ip addr show
  docker exec red3 ping -c 3 red4
}

run_dual_homed() {
  docker rm -f blue3 2>/dev/null || true
  docker run -dit --name blue3 nginxdemos/hello

  # Fails before attaching blue3 to red-bridge
  docker exec red1 ping -c 2 -W 2 blue3 || echo "Expected failure before connecting blue3 to ${BRIDGE_NAME}"

  # Attach blue3 as a dual-homed container across default bridge and red-bridge
  docker network connect "$BRIDGE_NAME" blue3
  docker exec red1 ping -c 3 blue3
}

run_ipvlan_same_subnet() {
  # Note: For VNet reachability across Azure hosts, register 10.1.1.10 and 10.1.1.11
  # as secondary IP configurations on the host Azure NIC.
  docker rm -f purple1 purple2 2>/dev/null || true
  docker network rm "$IPVLAN_NAME" 2>/dev/null || true

  docker network create --driver ipvlan \
    --subnet "$VNET_SUBNET" \
    --opt "parent=${PARENT_IF}" \
    --opt ipvlan_mode=l3 \
    "$IPVLAN_NAME"
  docker network inspect "$IPVLAN_NAME"

  docker run -d --net="$IPVLAN_NAME" --ip=10.1.1.10 --name purple1 alpine sh -c "while true; do sleep 3600; done"
  docker run -d --net="$IPVLAN_NAME" --ip=10.1.1.11 --name purple2 alpine sh -c "while true; do sleep 3600; done"
  docker exec purple1 ping -c 3 10.1.1.11
}

run_ipvlan_routed() {
  # Demonstrates multi-subnet L3 ipvlan routing (requires Azure UDR + NIC IP forwarding
  # for cross-host return traffic, and NVA SNAT for 0.0.0.0/0 internet egress).
  docker rm -f purple1 purple2 2>/dev/null || true
  docker network rm "$IPVLAN_NAME" 2>/dev/null || true

  docker network create --driver ipvlan \
    --subnet 192.168.1.0/24 \
    --subnet 192.168.2.0/24 \
    --opt "parent=${PARENT_IF}" \
    --opt ipvlan_mode=l3 \
    "$IPVLAN_NAME"
  docker network inspect "$IPVLAN_NAME"

  docker run -d --net="$IPVLAN_NAME" --ip=192.168.1.10 --name purple1 alpine sh -c "while true; do sleep 3600; done"
  docker run -d --net="$IPVLAN_NAME" --ip=192.168.2.10 --name purple2 alpine sh -c "while true; do sleep 3600; done"
  docker exec purple1 ping -c 3 192.168.2.10
}

run_cleanup() {
  local ids
  ids=$(docker ps -aq || true)
  if [[ -n "$ids" ]]; then
    # shellcheck disable=SC2086
    docker rm -f $ids
  fi
  docker network rm "$BRIDGE_NAME" 2>/dev/null || true
  docker network rm "$IPVLAN_NAME" 2>/dev/null || true
}

case "$STAGE" in
  basics)             run_basics ;;
  bridge-host1)       run_bridge_host1 ;;
  bridge-host2)       run_bridge_host2 ;;
  dual-homed)         run_dual_homed ;;
  ipvlan-same-subnet) run_ipvlan_same_subnet ;;
  ipvlan-routed)      run_ipvlan_routed ;;
  cleanup)            run_cleanup ;;
  *)
    echo "Lab context: RG=${RG}, LOCATION=${LOCATION}, PARENT_IF=${PARENT_IF}"
    echo "Usage: $0 {basics|bridge-host1|bridge-host2|dual-homed|ipvlan-same-subnet|ipvlan-routed|cleanup}"
    ;;
esac

