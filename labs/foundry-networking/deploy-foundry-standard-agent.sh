#!/usr/bin/env bash
# ==============================================================================
# Deploy Microsoft Foundry Standard Agent BYO-VNet Lab
#
# Validates and deploys build-foundry-standard-agent-vnet.bicep into an isolated
# Spoke VNet (or Hub-and-Spoke topology when DEPLOY_HUB_VNET=true) with full
# Private Link + Private DNS isolation and Microsoft.App/environments delegation.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_FILE="${SCRIPT_DIR}/build-foundry-standard-agent-vnet.bicep"

NAME_PREFIX="${NAME_PREFIX:-foundrylab}"
LOCATION="${LOCATION:-eastus2}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${NAME_PREFIX}-${LOCATION}}"
DEPLOY_HUB_VNET="${DEPLOY_HUB_VNET:-false}"
DEPLOY_MODEL="${DEPLOY_MODEL:-true}"
DEPLOY_CAPABILITY_HOSTS="${DEPLOY_CAPABILITY_HOSTS:-true}"

echo "==> [1/4] Registering required Azure resource providers..."
REQUIRED_PROVIDERS=(
  Microsoft.CognitiveServices
  Microsoft.App
  Microsoft.ContainerService
  Microsoft.Storage
  Microsoft.KeyVault
  Microsoft.DocumentDB
  Microsoft.Search
  Microsoft.Network
)
for rp in "${REQUIRED_PROVIDERS[@]}"; do
  az provider register --namespace "$rp" --output none
done

echo "==> [2/4] Compiling Bicep template locally..."
az bicep build --file "$BICEP_FILE" --stdout > /dev/null
echo "    Bicep compilation succeeded."

echo "==> [3/4] Creating resource group ${RESOURCE_GROUP} (${LOCATION}) and running ARM preflight validation..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

az deployment group validate \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters \
    location="$LOCATION" \
    namePrefix="$NAME_PREFIX" \
    deployHubVnet="$DEPLOY_HUB_VNET" \
    deployModel="$DEPLOY_MODEL" \
    deployCapabilityHosts="$DEPLOY_CAPABILITY_HOSTS" \
  --output none

echo "==> [4/4] Deploying Microsoft Foundry Standard Agent BYO-VNet stack..."
DEPLOYMENT_NAME="foundry-byovnet-$(date +%Y%m%d%H%M%S)"
az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters \
    location="$LOCATION" \
    namePrefix="$NAME_PREFIX" \
    deployHubVnet="$DEPLOY_HUB_VNET" \
    deployModel="$DEPLOY_MODEL" \
    deployCapabilityHosts="$DEPLOY_CAPABILITY_HOSTS" \
  --query "properties.outputs" \
  --output json

FOUNDRY_NAME=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" --query "properties.outputs.foundryAccountName.value" -o tsv | tr -d '\r')

echo ""
echo "=============================================================================="
echo "Deployment Complete: ${FOUNDRY_NAME}"
echo "=============================================================================="
echo "Verify Private Endpoints:"
echo "  az network private-endpoint list -g ${RESOURCE_GROUP} -o table"
echo ""
echo "Verify Private DNS resolution from a VM/Bastion inside the VNet:"
echo "  nslookup ${FOUNDRY_NAME}.cognitiveservices.azure.com 168.63.129.16"
echo "  nslookup ${FOUNDRY_NAME}.openai.azure.com 168.63.129.16"
echo "  nslookup ${FOUNDRY_NAME}.services.ai.azure.com 168.63.129.16"
echo ""
echo "IMPORTANT — Teardown Order (releases Microsoft.App/environments subnet link):"
echo "  1. az cognitiveservices account delete -g ${RESOURCE_GROUP} -n ${FOUNDRY_NAME}"
echo "  2. az cognitiveservices account purge  -g ${RESOURCE_GROUP} -n ${FOUNDRY_NAME} -l ${LOCATION}"
echo "  3. az group delete -n ${RESOURCE_GROUP} --yes --no-wait"
