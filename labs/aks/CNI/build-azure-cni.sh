#!/usr/bin/env bash
# ==============================================================================
# Lab: AKS with Traditional Azure CNI (Flat VNet Pod IP Allocation)
#
# Documentation:
#   https://learn.microsoft.com/azure/aks/configure-azure-cni
#
# Note: Traditional Azure CNI assigns every pod an IP directly from the VNet
# subnet. For most new deployments, prefer Azure CNI Overlay
# (build-azure-cni-overlay.sh) or Azure CNI Powered by Cilium
# (build-azure-cni-powered-by-cilium.sh) to avoid VNet IP exhaustion.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifests"

# ------------------------------------------------------------------------------
# Variables (Brownfield: existing VNet and dedicated AKS node/pod subnet)
# ------------------------------------------------------------------------------
MYACR="${MYACR:-<your-acr-name>}"
VNETRG="${VNETRG:-<your-vnet-rg>}"
VNET="${VNET:-<your-vnet-name>}"
SUBNET="${SUBNET:-<your-subnet-name>}"
RG="${RG:-<your-aks-rg>}"
AKSCLUSTER="${AKSCLUSTER:-<your-aks-cluster>}"
AKSDNS="${AKSDNS:-<your-aks-dns-prefix>}"
LOC="${LOC:-eastus2}"
NODE_VM_SIZE="${NODE_VM_SIZE:-Standard_D2s_v5}"
IDENTITY="${IDENTITY:-${AKSCLUSTER}-mi}"

# Validate current Azure subscription
az account show -o table

# Create resource group and Azure Container Registry
az group create --name "$RG" --location "$LOC"
az acr create --resource-group "$RG" --name "$MYACR" --sku Basic

# Resolve existing VNet and Subnet resource IDs
VNET_ID=$(az network vnet show --resource-group "$VNETRG" --name "$VNET" --query id -o tsv | tr -d '\r')
SUBNET_ID=$(az network vnet subnet show --resource-group "$VNETRG" --vnet-name "$VNET" --name "$SUBNET" --query id -o tsv | tr -d '\r')

# Create User-Assigned Managed Identity and grant Network Contributor on VNet
az identity create --name "$IDENTITY" --resource-group "$RG"
principal_id=$(az identity show --resource-group "$RG" --name "$IDENTITY" --query principalId -o tsv | tr -d '\r')
identity_id=$(az identity show --resource-group "$RG" --name "$IDENTITY" --query id -o tsv | tr -d '\r')

sleep 30
az role assignment create \
  --assignee-object-id "$principal_id" \
  --assignee-principal-type ServicePrincipal \
  --scope "$VNET_ID" \
  --role "Network Contributor"

# Create AKS cluster using Traditional Azure CNI (Standard_D2s_v5)
az aks create \
  --resource-group "$RG" \
  --name "$AKSCLUSTER" \
  --location "$LOC" \
  --node-count 3 \
  --node-vm-size "$NODE_VM_SIZE" \
  --generate-ssh-keys \
  --dns-name-prefix "$AKSDNS" \
  --network-plugin azure \
  --service-cidr 10.101.0.0/16 \
  --dns-service-ip 10.101.0.10 \
  --vnet-subnet-id "$SUBNET_ID" \
  --assign-identity "$identity_id" \
  --attach-acr "$MYACR" \
  --max-pods 30

# Connect and verify node + pod VNet IP addressing
az aks get-credentials -g "$RG" -n "$AKSCLUSTER" --overwrite-existing
kubectl get nodes -o wide

# Deploy shared lab manifests (ClusterIP, Internal LB, External LB, netshoot pod)
kubectl apply -f "${MANIFEST_DIR}/network-tools-pod.yaml"
kubectl apply -f "${MANIFEST_DIR}/demo-workload.yaml"
kubectl get pods,svc -n demo-ns -o wide

# Troubleshooting & DNS checks:
# kubectl get events -n demo-ns
# kubectl describe service web-internal-lb -n demo-ns
# kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
# kubectl exec -it network-tools -- curl -s ifconfig.me
#
# Cleanup:
# kubectl delete -f "${MANIFEST_DIR}/demo-workload.yaml"
# az group delete --name "$RG" --yes --no-wait
