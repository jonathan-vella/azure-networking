#!/usr/bin/env bash
# ==============================================================================
# Lab: AKS with Azure CNI Overlay (Private Pod CIDR + VNet Node Subnet)
#
# Documentation:
#   https://learn.microsoft.com/azure/aks/concepts-network-azure-cni-overlay
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifests"

# ------------------------------------------------------------------------------
# Variables (Brownfield BYO-VNet or standalone defaults)
# ------------------------------------------------------------------------------
PREFIX="${PREFIX:-aks-overlay}"
LOCATION="${LOCATION:-${LOC:-eastus2}}"
RG="${RG:-${PREFIX}-rg}"
VNETRG="${VNETRG:-${RG}}"
VNET="${VNET:-${PREFIX}-vnet}"
VNET_CIDR="${VNET_CIDR:-10.41.0.0/16}"
SUBNET_NAME="${SUBNET_NAME:-snet-aks-nodes}"
SUBNET_CIDR="${SUBNET_CIDR:-10.41.1.0/24}"
AKSCLUSTER="${AKSCLUSTER:-${PREFIX}-cluster}"
AKSDNS="${AKSDNS:-${PREFIX}-dns}"
NODE_VM_SIZE="${NODE_VM_SIZE:-Standard_D2s_v5}"
IDENTITY="${IDENTITY:-${AKSCLUSTER}-mi}"
CLEAN_PREFIX="$(printf '%s' "$PREFIX" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' | cut -c1-16)"
MYACR="${MYACR:-${CLEAN_PREFIX}acr${RANDOM}}"

az account show -o table
az provider register -n Microsoft.ContainerService --output none

# Create resource group, ACR, and User-Assigned Managed Identity
az group create --name "$RG" --location "$LOCATION"
az acr create --resource-group "$RG" --name "$MYACR" --sku Basic
az identity create --name "$IDENTITY" --resource-group "$RG"

# Create VNet and AKS node subnet when not attaching to a pre-existing brownfield VNet
if ! az network vnet subnet show --resource-group "$VNETRG" --vnet-name "$VNET" --name "$SUBNET_NAME" --output none 2>/dev/null; then
  az group create --name "$VNETRG" --location "$LOCATION" --output none
  az network vnet create \
    --resource-group "$VNETRG" \
    --name "$VNET" \
    --location "$LOCATION" \
    --address-prefixes "$VNET_CIDR" \
    --subnet-name "$SUBNET_NAME" \
    --subnet-prefixes "$SUBNET_CIDR" \
    --output none
fi

principal_id=$(az identity show --resource-group "$RG" --name "$IDENTITY" --query principalId -o tsv | tr -d '\r')
identity_id=$(az identity show --resource-group "$RG" --name "$IDENTITY" --query id -o tsv | tr -d '\r')

VNET_ID=$(az network vnet show --resource-group "$VNETRG" --name "$VNET" --query id -o tsv | tr -d '\r')
SUBNET_ID=$(az network vnet subnet show --resource-group "$VNETRG" --vnet-name "$VNET" --name "$SUBNET_NAME" --query id -o tsv | tr -d '\r')

# Grant Network Contributor on the target VNet so AKS can manage Internal Load Balancers
sleep 30
az role assignment create \
  --assignee-object-id "$principal_id" \
  --assignee-principal-type ServicePrincipal \
  --scope "$VNET_ID" \
  --role "Network Contributor"

# Create AKS cluster with Azure CNI Overlay and Standard_D2s_v5 nodes
az aks create \
  --resource-group "$RG" \
  --name "$AKSCLUSTER" \
  --location "$LOCATION" \
  --node-count 3 \
  --node-vm-size "$NODE_VM_SIZE" \
  --generate-ssh-keys \
  --dns-name-prefix "$AKSDNS" \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --service-cidr 10.101.0.0/16 \
  --dns-service-ip 10.101.0.10 \
  --pod-cidr 10.244.0.0/16 \
  --vnet-subnet-id "$SUBNET_ID" \
  --assign-identity "$identity_id" \
  --attach-acr "$MYACR" \
  --max-pods 100

az aks get-credentials -g "$RG" -n "$AKSCLUSTER" --overwrite-existing
kubectl get nodes -o wide

# Deploy shared test workload and network-tools pod
kubectl apply -f "${MANIFEST_DIR}/network-tools-pod.yaml"
kubectl apply -f "${MANIFEST_DIR}/demo-workload.yaml"
kubectl get pods,svc -n demo-ns -o wide

# Verify inbound/outbound connectivity and CoreDNS:
# kubectl exec -it network-tools -- curl -s ifconfig.me
# kubectl exec -it network-tools -- curl -s http://echo-red.demo-ns.svc.cluster.local:8080
# kubectl describe service web-external-lb -n demo-ns
# kubectl describe service web-internal-lb -n demo-ns
# kubectl get pods -n kube-system -l k8s-app=kube-dns
#
# Cleanup:
# kubectl delete ns demo-ns
# az group delete --name "$RG" --yes --no-wait
