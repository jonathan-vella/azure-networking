#!/usr/bin/env bash
# ==============================================================================
# Build Customer Spoke VNet + Jumpbox VMs for Private AI / ML Workspace Testing
#
# Creates:
#   - Customer VNet (10.100.0.0/16) with vm-subnet and private-endpoint-subnet
#     (privateEndpointNetworkPolicies disabled)
#   - Linux diagnostic jumpbox (Ubuntu 24.04, Standard_B2ls_v2) using local cloud-init.txt
#   - Optional Windows jumpbox (Windows Server 2022, Standard_D2s_v5) when
#     DEPLOY_WINDOWS_VM=true and ADMIN_PASSWORD is supplied
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PREFIX="${PREFIX:-ml-private}"
export LOCATION="${LOCATION:-eastus2}"
export RG="${RG:-${COMMON_RESOURCE_GROUP:-${PREFIX}-common-rg}}"
export COMMON_RESOURCE_GROUP="$RG"
export LINUX_VM="${LINUX_VM:-ai-jumpbox-linux}"
export LINUX_IMAGE="${LINUX_IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"
export LINUX_VM_SIZE="${LINUX_VM_SIZE:-Standard_B2ls_v2}"
export DEPLOY_WINDOWS_VM="${DEPLOY_WINDOWS_VM:-false}"
export WINDOWS_VM="${WINDOWS_VM:-ai-jumpbox-win}"
export WINDOWS_IMAGE="${WINDOWS_IMAGE:-Win2022Datacenter}"
export WINDOWS_VM_SIZE="${WINDOWS_VM_SIZE:-Standard_D2s_v5}"
export ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
export VNET_NAME="${VNET_NAME:-customer-vnet}"
export PEP_SUBNET_NAME="${PEP_SUBNET_NAME:-private-endpoint-subnet}"
export VM_SUBNET_NAME="${VM_SUBNET_NAME:-vm-subnet}"
export VNET_ADDRESS_PREFIX="${VNET_ADDRESS_PREFIX:-10.100.0.0/16}"
export VM_SUBNET_PREFIX="${VM_SUBNET_PREFIX:-10.100.2.0/24}"
export PEP_SUBNET_PREFIX="${PEP_SUBNET_PREFIX:-10.100.3.0/24}"
export NSG_NAME="${NSG_NAME:-vm-jumpbox-nsg}"
export PUB_KEY="${PUB_KEY:-$HOME/.ssh/id_rsa.pub}"

MY_IP=$(curl -fsSL https://ifconfig.me | tr -d '\r\n')

az group create --name "$COMMON_RESOURCE_GROUP" --location "$LOCATION"

# Create VNet with jumpbox subnet and Private Endpoint subnet
az network vnet create \
  --resource-group "$COMMON_RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --location "$LOCATION" \
  --address-prefixes "$VNET_ADDRESS_PREFIX"

az network vnet subnet create \
  --resource-group "$COMMON_RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$VM_SUBNET_NAME" \
  --address-prefixes "$VM_SUBNET_PREFIX"

az network vnet subnet create \
  --resource-group "$COMMON_RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$PEP_SUBNET_NAME" \
  --address-prefixes "$PEP_SUBNET_PREFIX" \
  --private-endpoint-network-policies Disabled

# Create NSG allowing SSH (and RDP when Windows jumpbox is enabled) from client IP only
az network nsg create --resource-group "$COMMON_RESOURCE_GROUP" --name "$NSG_NAME"

az network nsg rule create \
  --resource-group "$COMMON_RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name AllowSSH \
  --protocol Tcp \
  --priority 1000 \
  --destination-port-ranges 22 \
  --source-address-prefixes "${MY_IP}/32" \
  --access Allow

# Create Linux jumpbox VM using shared local cloud-init.txt
az vm create \
  --resource-group "$COMMON_RESOURCE_GROUP" \
  --name "$LINUX_VM" \
  --image "$LINUX_IMAGE" \
  --size "$LINUX_VM_SIZE" \
  --admin-username "$ADMIN_USERNAME" \
  --ssh-key-values "$PUB_KEY" \
  --public-ip-sku Standard \
  --vnet-name "$VNET_NAME" \
  --subnet "$VM_SUBNET_NAME" \
  --nsg "$NSG_NAME" \
  --custom-data "${SCRIPT_DIR}/cloud-init.txt"

LINUX_VM_IP=$(az vm show -g "$COMMON_RESOURCE_GROUP" -n "$LINUX_VM" --show-details --query publicIps -o tsv | tr -d '\r')
echo "Linux Jumpbox Public IP: ${LINUX_VM_IP} (ssh ${ADMIN_USERNAME}@${LINUX_VM_IP})"

if [[ "$DEPLOY_WINDOWS_VM" == "true" ]]; then
  : "${ADMIN_PASSWORD:?Set ADMIN_PASSWORD in your environment when DEPLOY_WINDOWS_VM=true}"

  az network nsg rule create \
    --resource-group "$COMMON_RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name AllowRDP \
    --protocol Tcp \
    --priority 1010 \
    --destination-port-ranges 3389 \
    --source-address-prefixes "${MY_IP}/32" \
    --access Allow

  az vm create \
    --resource-group "$COMMON_RESOURCE_GROUP" \
    --name "$WINDOWS_VM" \
    --image "$WINDOWS_IMAGE" \
    --size "$WINDOWS_VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --public-ip-sku Standard \
    --vnet-name "$VNET_NAME" \
    --subnet "$VM_SUBNET_NAME" \
    --nsg "$NSG_NAME"

  WINDOWS_VM_IP=$(az vm show -g "$COMMON_RESOURCE_GROUP" -n "$WINDOWS_VM" --show-details --query publicIps -o tsv | tr -d '\r')
  echo "Windows Jumpbox Public IP: ${WINDOWS_VM_IP} (mstsc /v:${WINDOWS_VM_IP})"
fi
