#!/usr/bin/env bash
# ==============================================================================
# Lab: AKS Ingress with Application Gateway for Containers (Gateway API)
#
# Provisions:
#   1. Custom VNet with AKS Node Subnet (/24) and delegated AGC Subnet (/24,
#      delegated to Microsoft.ServiceNetworking/trafficControllers)
#   2. AKS cluster running Azure CNI Overlay Powered by Cilium, OIDC Issuer,
#      and Microsoft Entra Workload Identity (Standard_D2s_v5 nodes)
#   3. User-Assigned Managed Identity federated with ALB Controller ServiceAccount
#      + least-privilege RBAC (AppGw for Containers Configuration Manager on MC_
#      RG, Reader on MC_ RG, Network Contributor on delegated AGC subnet)
#   4. Application Gateway for Containers ALB Controller installed via OCI Helm
#   5. ApplicationLoadBalancer CR + Gateway API manifests (Gateway + HTTPRoute)
#
# Reference:
#   https://learn.microsoft.com/azure/application-gateway/for-containers/overview
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_PATH="${SCRIPT_DIR}/../manifests/gateway-api-routes.yaml"

# ------------------------------------------------------------------------------
# 1. Configuration Variables (override via environment variables as needed)
# ------------------------------------------------------------------------------
PREFIX="${PREFIX:-aks-agc}"
LOCATION="${LOCATION:-eastus2}"
RG="${RG:-${PREFIX}-rg}"
AKS_NAME="${AKS_NAME:-${PREFIX}-cluster}"
NODE_VM_SIZE="${NODE_VM_SIZE:-Standard_D2s_v5}"
NODE_COUNT="${NODE_COUNT:-3}"

VNET_NAME="${VNET_NAME:-${PREFIX}-vnet}"
VNET_CIDR="${VNET_CIDR:-10.40.0.0/16}"
AKS_SUBNET_NAME="${AKS_SUBNET_NAME:-snet-aks-nodes}"
AKS_SUBNET_CIDR="${AKS_SUBNET_CIDR:-10.40.1.0/24}"
ALB_SUBNET_NAME="${ALB_SUBNET_NAME:-snet-agc-alb}"
ALB_SUBNET_CIDR="${ALB_SUBNET_CIDR:-10.40.2.0/24}" # Must have >= 250 IPs (/24 or larger)

CLUSTER_IDENTITY_NAME="${CLUSTER_IDENTITY_NAME:-${PREFIX}-cluster-mi}"
ALB_IDENTITY_NAME="${ALB_IDENTITY_NAME:-azure-alb-identity}"
ALB_CONTROLLER_NAMESPACE="azure-alb-system"
ALB_HELM_NAMESPACE="alb-helm"
ALB_CHART_VERSION="${ALB_CHART_VERSION:-1.13.0}"

# Built-in Azure RBAC Role Definition IDs
ROLE_READER="acdd72a7-3385-48ef-bd42-f606fba81ae7"
ROLE_NETWORK_CONTRIBUTOR="4d97b98b-1d4f-4787-a291-c67834d212e7"
ROLE_AGC_CONFIG_MANAGER="fbc52c3f-28ad-4303-a892-8a056630b8f1"

echo "==> [1/8] Registering required Azure resource providers..."
for rp in Microsoft.ContainerService Microsoft.Network Microsoft.NetworkFunction Microsoft.ServiceNetworking; do
  az provider register --namespace "$rp" --output none
done
az extension add --name alb --upgrade --yes 2>/dev/null || true

echo "==> [2/8] Creating resource group and VNet with delegated AGC subnet..."
az group create --name "$RG" --location "$LOCATION" --output none

az network vnet create \
  --resource-group "$RG" \
  --name "$VNET_NAME" \
  --location "$LOCATION" \
  --address-prefixes "$VNET_CIDR" \
  --subnet-name "$AKS_SUBNET_NAME" \
  --subnet-prefixes "$AKS_SUBNET_CIDR" \
  --output none

az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET_NAME" \
  --name "$ALB_SUBNET_NAME" \
  --address-prefixes "$ALB_SUBNET_CIDR" \
  --delegations "Microsoft.ServiceNetworking/trafficControllers" \
  --output none

VNET_ID=$(az network vnet show -g "$RG" -n "$VNET_NAME" --query id -o tsv | tr -d '\r')
AKS_SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET_NAME" -n "$AKS_SUBNET_NAME" --query id -o tsv | tr -d '\r')
ALB_SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET_NAME" -n "$ALB_SUBNET_NAME" --query id -o tsv | tr -d '\r')

echo "==> [3/8] Creating cluster Managed Identity and granting VNet permissions..."
az identity create --resource-group "$RG" --name "$CLUSTER_IDENTITY_NAME" --output none
CLUSTER_MI_ID=$(az identity show -g "$RG" -n "$CLUSTER_IDENTITY_NAME" --query id -o tsv | tr -d '\r')
CLUSTER_MI_PRINCIPAL_ID=$(az identity show -g "$RG" -n "$CLUSTER_IDENTITY_NAME" --query principalId -o tsv | tr -d '\r')

sleep 30
az role assignment create \
  --assignee-object-id "$CLUSTER_MI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$VNET_ID" \
  --role "$ROLE_NETWORK_CONTRIBUTOR" \
  --output none

echo "==> [4/8] Provisioning AKS cluster (Azure CNI Overlay + Cilium + OIDC + Workload Identity)..."
az aks create \
  --resource-group "$RG" \
  --name "$AKS_NAME" \
  --location "$LOCATION" \
  --node-count "$NODE_COUNT" \
  --node-vm-size "$NODE_VM_SIZE" \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --network-dataplane cilium \
  --pod-cidr 192.168.0.0/16 \
  --service-cidr 10.101.0.0/16 \
  --dns-service-ip 10.101.0.10 \
  --vnet-subnet-id "$AKS_SUBNET_ID" \
  --assign-identity "$CLUSTER_MI_ID" \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --generate-ssh-keys \
  --output none

az aks get-credentials --resource-group "$RG" --name "$AKS_NAME" --overwrite-existing

echo "==> [5/8] Creating ALB Controller Workload Identity, RBAC, and OIDC Federation..."
MC_RG=$(az aks show -g "$RG" -n "$AKS_NAME" --query nodeResourceGroup -o tsv | tr -d '\r')
MC_RG_ID=$(az group show -n "$MC_RG" --query id -o tsv | tr -d '\r')
AKS_OIDC_ISSUER=$(az aks show -g "$RG" -n "$AKS_NAME" --query "oidcIssuerProfile.issuerUrl" -o tsv | tr -d '\r')

az identity create --resource-group "$RG" --name "$ALB_IDENTITY_NAME" --output none
ALB_MI_PRINCIPAL_ID=$(az identity show -g "$RG" -n "$ALB_IDENTITY_NAME" --query principalId -o tsv | tr -d '\r')
ALB_MI_CLIENT_ID=$(az identity show -g "$RG" -n "$ALB_IDENTITY_NAME" --query clientId -o tsv | tr -d '\r')

echo "    Waiting 60 seconds for Microsoft Entra ID replication..."
sleep 60

az role assignment create \
  --assignee-object-id "$ALB_MI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$MC_RG_ID" \
  --role "$ROLE_READER" \
  --output none

az role assignment create \
  --assignee-object-id "$ALB_MI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$MC_RG_ID" \
  --role "$ROLE_AGC_CONFIG_MANAGER" \
  --output none

az role assignment create \
  --assignee-object-id "$ALB_MI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$ALB_SUBNET_ID" \
  --role "$ROLE_NETWORK_CONTRIBUTOR" \
  --output none

az identity federated-credential create \
  --name "azure-alb-fic" \
  --identity-name "$ALB_IDENTITY_NAME" \
  --resource-group "$RG" \
  --issuer "$AKS_OIDC_ISSUER" \
  --subject "system:serviceaccount:${ALB_CONTROLLER_NAMESPACE}:alb-controller-sa" \
  --audiences "api://AzureADTokenExchange" \
  --output none

echo "==> [6/8] Installing Managed ALB Controller via Helm (${ALB_CHART_VERSION})..."
helm upgrade --install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller \
  --namespace "$ALB_HELM_NAMESPACE" \
  --create-namespace \
  --version "$ALB_CHART_VERSION" \
  --set albController.namespace="$ALB_CONTROLLER_NAMESPACE" \
  --set albController.podIdentity.clientID="$ALB_MI_CLIENT_ID" \
  --wait

kubectl get pods -n "$ALB_CONTROLLER_NAMESPACE"
kubectl wait --for=condition=Accepted gatewayclass/azure-alb-external --timeout=120s

echo "==> [7/8] Provisioning ApplicationLoadBalancer CR associated with delegated subnet..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: alb-infra
---
apiVersion: alb.networking.azure.io/v1
kind: ApplicationLoadBalancer
metadata:
  name: agc-alb
  namespace: alb-infra
spec:
  associations:
    - ${ALB_SUBNET_ID}
EOF

echo "    Waiting for Application Gateway for Containers resource deployment (typically 4-6 minutes)..."
kubectl wait --for=condition=Deployment applicationloadbalancer/agc-alb -n alb-infra --timeout=600s

echo "==> [8/8] Applying Gateway API manifests (${MANIFEST_PATH})..."
kubectl apply -f "$MANIFEST_PATH"
kubectl wait --for=condition=Programmed gateway/agc-gateway -n agc-demo --timeout=300s

AGC_FQDN=$(kubectl get gateway agc-gateway -n agc-demo -o jsonpath='{.status.addresses[0].value}')
echo ""
echo "=============================================================================="
echo "Application Gateway for Containers Ready!"
echo "Frontend FQDN: http://${AGC_FQDN}"
echo "=============================================================================="
echo "Test default route (web-v1):"
echo "  curl -s http://${AGC_FQDN}/"
echo ""
echo "Test path-based route (/orders -> orders-api):"
echo "  curl -s http://${AGC_FQDN}/orders"
echo ""
echo "Test header-based canary route (X-Canary: true -> web-v2):"
echo "  curl -s -H 'X-Canary: true' http://${AGC_FQDN}/"
echo ""
echo "Cleanup when finished:"
echo "  az group delete --name ${RG} --yes --no-wait"
