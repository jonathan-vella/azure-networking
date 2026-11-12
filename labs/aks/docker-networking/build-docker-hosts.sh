#!/usr/bin/env bash
# ==============================================================================
# Build two Linux VMs with Docker Engine and Linux network tools for L2/L3
# bridge and ipvlan container networking experiments.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-docker-net-rg}"
export LOCATION="${LOCATION:-eastus2}"
export VM_NAME_1="${VM_NAME_1:-docker-host-1}"
export VM_NAME_2="${VM_NAME_2:-docker-host-2}"
export VM_IMAGE="${VM_IMAGE:-Ubuntu2404}"
export VM_SIZE="${VM_SIZE:-Standard_B2ls_v2}"
export ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
export VNET_NAME="${VNET_NAME:-docker-vnet}"
export SUBNET_NAME="${SUBNET_NAME:-docker-subnet}"
export VNET_ADDRESS_PREFIX="${VNET_ADDRESS_PREFIX:-10.1.0.0/16}"
export SUBNET_ADDRESS_PREFIX="${SUBNET_ADDRESS_PREFIX:-10.1.1.0/24}"
export PUB_KEY="${PUB_KEY:-$HOME/.ssh/id_rsa.pub}"

MY_IP=$(curl -s https://ifconfig.me)

az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"

az network vnet create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$VNET_NAME" \
  --address-prefixes "$VNET_ADDRESS_PREFIX" \
  --subnet-name "$SUBNET_NAME" \
  --subnet-prefixes "$SUBNET_ADDRESS_PREFIX"

create_vm() {
  local vm_name=$1
  local nsg_name="${vm_name}-nsg"

  az vm create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$vm_name" \
    --image "$VM_IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --ssh-key-values "$PUB_KEY" \
    --public-ip-sku Standard \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --custom-data "${SCRIPT_DIR}/cloud-init.txt"

  az network nsg create --resource-group "$RESOURCE_GROUP_NAME" --name "$nsg_name"

  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --nsg-name "$nsg_name" \
    --name AllowSSH \
    --protocol Tcp \
    --priority 1000 \
    --destination-port-ranges 22 \
    --source-address-prefixes "${MY_IP}/32" \
    --access Allow

  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --nsg-name "$nsg_name" \
    --name AllowHTTP8080 \
    --protocol Tcp \
    --priority 1010 \
    --destination-port-ranges 8080 \
    --source-address-prefixes "${MY_IP}/32" \
    --access Allow

  local nic_name
  nic_name=$(az vm show --resource-group "$RESOURCE_GROUP_NAME" --name "$vm_name" \
    --query "networkProfile.networkInterfaces[0].id" --output tsv | tr -d '\r' | xargs -n 1 basename)
  az network nic update --resource-group "$RESOURCE_GROUP_NAME" --name "$nic_name" --network-security-group "$nsg_name"
}

create_vm "$VM_NAME_1"
create_vm "$VM_NAME_2"

VM1_IP=$(az vm show --resource-group "$RESOURCE_GROUP_NAME" --name "$VM_NAME_1" --show-details --query publicIps --output tsv | tr -d '\r')
VM2_IP=$(az vm show --resource-group "$RESOURCE_GROUP_NAME" --name "$VM_NAME_2" --show-details --query publicIps --output tsv | tr -d '\r')

echo "VM1 Public IP: $VM1_IP (ssh ${ADMIN_USERNAME}@${VM1_IP})"
echo "VM2 Public IP: $VM2_IP (ssh ${ADMIN_USERNAME}@${VM2_IP})"
