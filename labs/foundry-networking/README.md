# Microsoft Foundry & Private AI Networking Labs

Deployable Bicep and Azure CLI labs for isolating **Microsoft Foundry (AI Services & Projects) Standard Agents** with Bring-Your-Own Virtual Network (BYO-VNet) subnet injection, Private Link, and Private DNS—alongside private **Azure Machine Learning** managed-network workspace patterns.

> **Field Architect Handbook:** See **[Workload Networking — Microsoft Foundry & AI](../../src/content/docs/05-workload-networking/)** for subnet sizing rules, Service Association Link lifecycles, DNS forwarding, and Azure Firewall allow-lists.

---

## Lab Contents

| Path | Description |
| --- | --- |
| [`build-foundry-standard-agent-vnet.bicep`](build-foundry-standard-agent-vnet.bicep) | End-to-end Bicep template for **Microsoft Foundry Standard Agent BYO-VNet** (isolated Spoke VNet or peered Hub-and-Spoke), Private Endpoints, 7 Private DNS Zones, BYO Storage / Key Vault / Cosmos DB / AI Search (`publicNetworkAccess: 'Disabled'`), Project connections, RBAC, and Capability Hosts. |
| [`deploy-foundry-standard-agent.sh`](deploy-foundry-standard-agent.sh) | Automated Azure CLI runner that registers resource providers, compiles & validates the Bicep template, deploys the stack, and prints verification and safe teardown commands. |
| [`ml-private-workspace/build-cust-vnet.sh`](ml-private-workspace/build-cust-vnet.sh) | Builds a customer VNet (`vm-subnet` + `private-endpoint-subnet`) with an NSG-locked `Standard_B2ls_v2` Linux jumpbox (and optional `Standard_D2s_v5` Windows jumpbox) using [`ml-private-workspace/cloud-init.txt`](ml-private-workspace/cloud-init.txt). |
| [`ml-private-workspace/build-workspace.sh`](ml-private-workspace/build-workspace.sh) | Provisions a private Azure Machine Learning workspace (`managed_approved`, `managed_internet`, or `byo_vnet`) with `amlworkspace` Private Endpoint and `privatelink.api.azureml.ms` / `privatelink.notebooks.azure.net` Private DNS zones. |

---

## 1. Microsoft Foundry Standard Agent BYO-VNet Lab

### Architecture Highlights

1. **Dedicated Agent Subnet (`snet-foundry-agent`, `/24`)** — Delegated exclusively to `Microsoft.App/environments` (`defaultOutboundAccess: false`) and injected into the Foundry account (`kind: 'AIServices'`, `allowProjectManagement: true`) via `networkInjections` (`scenario: 'agent'`, `useMicrosoftManagedNetwork: false`).
2. **Private Endpoint Subnet (`snet-private-endpoints`, `/24`)** — Configured with `privateEndpointNetworkPolicies: 'Disabled'` hosting Private Endpoints for:
   - **Microsoft Foundry Account** (`groupId: account`)
   - **Azure Storage Account** (`groupId: blob`) — agent file uploads
   - **Azure Cosmos DB for NoSQL** (`groupId: Sql`) — agent conversation threads & definitions
   - **Azure AI Search** (`groupId: searchService`) — agent vector stores
   - **Azure Key Vault** (`groupId: vault`) — enterprise secrets
3. **Complete Private DNS Topology** — Provisions and links all required Private DNS zones to the Spoke VNet (and optional Hub VNet when `deployHubVnet=true`):
   - `privatelink.cognitiveservices.azure.com`
   - `privatelink.openai.azure.com`
   - `privatelink.services.ai.azure.com`
   - `privatelink.blob.core.windows.net`
   - `privatelink.documents.azure.com`
   - `privatelink.search.windows.net`
   - `privatelink.vaultcore.azure.net`
4. **Zero Local Keys (`disableLocalAuth: true`)** — Enforces Microsoft Entra ID authentication across Foundry, Cosmos DB, Storage, Key Vault, and AI Search, wiring Project Managed Identity RBAC and Capability Hosts (`caphost-account` + `caphost-project`).

### Quickstart

```bash
# Deploy isolated Spoke VNet topology in eastus2
LOCATION=eastus2 NAME_PREFIX=foundrylab ./deploy-foundry-standard-agent.sh

# Or deploy with a peered Hub VNet (AzureFirewallSubnet + AzureBastionSubnet)
DEPLOY_HUB_VNET=true LOCATION=swedencentral NAME_PREFIX=foundryhub ./deploy-foundry-standard-agent.sh
```

> **Prerequisite for Capability Hosts:** When `deployCapabilityHosts=true` (default), ensure the deploying principal holds **Storage Blob Data Contributor** and **Cosmos DB Operator** at the subscription or resource-group scope, or run a two-stage deploy with `DEPLOY_CAPABILITY_HOSTS=false` first.

### Safe Teardown Order (Service Association Link)

Because `Microsoft.App/environments` injects a `legionservicelink` Service Association Link into `snet-foundry-agent`, **delete and purge** the Foundry account before deleting the VNet:

```bash
az cognitiveservices account delete -g "$RESOURCE_GROUP" -n "$FOUNDRY_NAME"
az cognitiveservices account purge  -g "$RESOURCE_GROUP" -n "$FOUNDRY_NAME" -l "$LOCATION"
az group delete -n "$RESOURCE_GROUP" --yes --no-wait
```

---

## 2. Azure Machine Learning Private Workspace Lab (`ml-private-workspace/`)

When running classic Azure Machine Learning registries, compute clusters, or managed online endpoints alongside Foundry:

```bash
cd ml-private-workspace
./build-cust-vnet.sh
NETWORK_MODE=managed_approved ./build-workspace.sh
```
