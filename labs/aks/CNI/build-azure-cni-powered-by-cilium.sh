#!/usr/bin/env bash
# ==============================================================================
# Lab: AKS with Azure CNI Powered by Cilium (Overlay Mode + eBPF Dataplane)
#
# Documentation:
#   https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium
#
# Replaces legacy kube-proxy iptables rules and standalone Calico binaries with
# Cilium eBPF service routing and native Kubernetes / Cilium Network Policies.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifests"

RG="${RG:-aks-cilium-rg}"
AKSCLUSTER="${AKSCLUSTER:-aks-cilium-lab}"
LOC="${LOC:-eastus2}"
NODE_VM_SIZE="${NODE_VM_SIZE:-Standard_D2s_v5}"
NODE_COUNT="${NODE_COUNT:-3}"

az account show -o table
az provider register -n Microsoft.ContainerService --output none

# Create Resource Group
az group create --name "$RG" --location "$LOC"

# Create AKS cluster with Azure CNI Overlay + Cilium eBPF dataplane
az aks create \
  --resource-group "$RG" \
  --name "$AKSCLUSTER" \
  --location "$LOC" \
  --node-count "$NODE_COUNT" \
  --node-vm-size "$NODE_VM_SIZE" \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --pod-cidr 192.168.0.0/16 \
  --network-dataplane cilium \
  --generate-ssh-keys

# Connect to cluster and inspect Cilium DaemonSet pods
az aks get-credentials -g "$RG" -n "$AKSCLUSTER" --overwrite-existing
kubectl get nodes -o wide
kubectl get pods -n kube-system -l k8s-app=cilium -o wide

# Deploy network diagnostic pod and multi-service demo workload
kubectl apply -f "${MANIFEST_DIR}/network-tools-pod.yaml"
kubectl apply -f "${MANIFEST_DIR}/demo-workload.yaml"
kubectl get pods,svc -n demo-ns -o wide

# Optional: Brownfield BYO-VNet variation
# When attaching to an existing subnet (--vnet-subnet-id "$SUBNET_ID"), create a
# user-assigned managed identity (--assign-identity "$USER_MI_ID") and grant
# "Network Contributor" on the VNet scope before running az aks create so
# internal/external LoadBalancer reconciliations succeed immediately.

# Inspect Cilium status inside a node agent pod:
# CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
# kubectl exec -n kube-system "$CILIUM_POD" -- cilium status --brief
#
# Cleanup:
# kubectl delete ns demo-ns
# az group delete --name "$RG" --yes --no-wait
