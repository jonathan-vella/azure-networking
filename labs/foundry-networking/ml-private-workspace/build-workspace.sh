#!/usr/bin/env bash
# ==============================================================================
# Build Private Azure Machine Learning Workspace (Managed Network + BYO-VNet PE)
#
# Documentation:
#   https://learn.microsoft.com/azure/machine-learning/how-to-managed-network
#
# Supported NETWORK_MODE values:
#   - managed_internet : Public inbound Disabled + Managed VNet (allow_internet_outbound)
#   - managed_approved : Public inbound Disabled + Managed VNet (allow_only_approved_outbound)
#   - byo_vnet         : Public inbound Disabled + Customer VNet Private Endpoint
#   - public           : Public network access Enabled (baseline comparison only)
# ==============================================================================
set -euo pipefail

PREFIX="${PREFIX:-aml-private-demo}"
NETWORK_MODE="${NETWORK_MODE:-managed_approved}"
export LOCATION="${LOCATION:-eastus2}"
export RG="${RG:-${RESOURCE_GROUP:-${PREFIX}-rg}}"
export RESOURCE_GROUP="$RG"
export WORKSPACE_NAME="${WORKSPACE_NAME:-${PREFIX}}"

# Customer VNet created by ./build-cust-vnet.sh (used for inbound Private Endpoint)
export COMMON_RESOURCE_GROUP="${COMMON_RESOURCE_GROUP:-ml-private-common-rg}"
export VNET_NAME="${VNET_NAME:-customer-vnet}"
export PEP_SUBNET_NAME="${PEP_SUBNET_NAME:-private-endpoint-subnet}"
export PRIVATE_ENDPOINT_NAME="${PRIVATE_ENDPOINT_NAME:-pe-${WORKSPACE_NAME}}"

az extension add --name ml --upgrade --yes 2>/dev/null || true
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Provision Premium Azure Container Registry (required for Private Link support)
CLEAN_PREFIX=$(echo "${PREFIX}${RANDOM}" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' | cut -c1-40)
export ACR_NAME="${CLEAN_PREFIX}acr"
ACR_ID=$(az acr create --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" --sku Premium --public-network-enabled false --query id -o tsv | tr -d '\r')

case "$NETWORK_MODE" in
  public)
    az ml workspace create \
      --name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --container-registry "$ACR_ID" \
      --public-network-access Enabled
    ;;
  byo_vnet)
    az ml workspace create \
      --name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --container-registry "$ACR_ID" \
      --public-network-access Disabled
    ;;
  managed_internet)
    az ml workspace create \
      --name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --container-registry "$ACR_ID" \
      --public-network-access Disabled \
      --managed-network allow_internet_outbound
    ;;
  managed_approved)
    az ml workspace create \
      --name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --container-registry "$ACR_ID" \
      --public-network-access Disabled \
      --managed-network allow_only_approved_outbound
    ;;
  *)
    echo "Unsupported NETWORK_MODE: $NETWORK_MODE" >&2
    exit 1
    ;;
esac

if [[ "$NETWORK_MODE" != "public" ]]; then
  echo "==> Creating inbound Private Endpoint and Private DNS zones in customer VNet..."
  WORKSPACE_ID=$(az ml workspace show --name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv | tr -d '\r')
  VNET_ID=$(az network vnet show -g "$COMMON_RESOURCE_GROUP" --name "$VNET_NAME" --query id -o tsv | tr -d '\r')
  PEP_SUBNET_ID=$(az network vnet subnet show -g "$COMMON_RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$PEP_SUBNET_NAME" --query id -o tsv | tr -d '\r')

  az network private-endpoint create \
    --name "$PRIVATE_ENDPOINT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --subnet "$PEP_SUBNET_ID" \
    --private-connection-resource-id "$WORKSPACE_ID" \
    --group-id amlworkspace \
    --connection-name "${WORKSPACE_NAME}-plsc" \
    --location "$LOCATION"

  for zone in privatelink.api.azureml.ms privatelink.notebooks.azure.net; do
    az network private-dns zone create -g "$RESOURCE_GROUP" --name "$zone"
    az network private-dns link vnet create \
      -g "$RESOURCE_GROUP" \
      --zone-name "$zone" \
      --name "${VNET_NAME}-link" \
      --virtual-network "$VNET_ID" \
      --registration-enabled false
  done

  az network private-endpoint dns-zone-group create \
    -g "$RESOURCE_GROUP" \
    --endpoint-name "$PRIVATE_ENDPOINT_NAME" \
    --name aml-zone-group \
    --private-dns-zone privatelink.api.azureml.ms \
    --zone-name privatelink-api-azureml-ms

  az network private-endpoint dns-zone-group add \
    -g "$RESOURCE_GROUP" \
    --endpoint-name "$PRIVATE_ENDPOINT_NAME" \
    --name aml-zone-group \
    --private-dns-zone privatelink.notebooks.azure.net \
    --zone-name privatelink-notebooks-azure-net
fi

echo ""
echo "Workspace ${WORKSPACE_NAME} (${NETWORK_MODE}) ready."
echo "Validate DNS from the Linux jumpbox inside ${VNET_NAME}:"
echo "  dig <online-endpoint-name>.${LOCATION}.inference.ml.azure.com +short"
echo ""
echo "Cleanup when finished:"
echo "  az ml workspace delete -n ${WORKSPACE_NAME} -g ${RESOURCE_GROUP} --all-resources --permanently-delete --yes"
echo "  az group delete -n ${RESOURCE_GROUP} --yes --no-wait"
