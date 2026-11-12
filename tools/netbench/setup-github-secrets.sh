#!/usr/bin/env bash
# Configure GitHub repository secrets for Azure Network Benchmark workflows.
# Supports environment variables, CLI flags, and optional non-interactive execution.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./setup-github-secrets.sh [options]

Options (all also configurable via environment variables):
  --subscription-id <id>          Target Azure subscription ID (env: AZURE_SUBSCRIPTION_ID)
  --state-subscription-id <id>    Terraform state subscription ID (env: TERRAFORM_STATE_SUBSCRIPTION_ID)
  --location <region>             Azure region for state/dashboard resources (env: AZURE_LOCATION, default: westeurope)
  --repo <owner/repo>             Target GitHub repository (env: GITHUB_REPOSITORY, default: detected or jonathan-vella/azure-networking)
  --state-rg <name>               Terraform state resource group (env: TERRAFORM_STATE_RG, default: rg-netbench-state-001)
  --state-sa <name>               Terraform state storage account (env: TERRAFORM_STATE_SA, default: sanetbenchstate001)
  --state-container <name>        Terraform state blob container (env: TERRAFORM_STATE_CONTAINER, default: tfstate)
  --webapp-rg <name>              Dashboard resource group (env: WEBAPP_RG, default: rg-netbench-dashboard-001)
  --webapp-sa <name>              Dashboard storage account (env: WEBAPP_SA, default: sanetbenchdashboard001)
  --sp-name <name>                Service principal display name (env: SP_NAME, default: azure-netbench-sp-<epoch>)
  -y, --yes                       Non-interactive mode; skip confirmation prompts (env: NON_INTERACTIVE=true)
  -h, --help                      Show this help message
EOF
}

SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
TERRAFORM_STATE_SUBSCRIPTION_ID="${TERRAFORM_STATE_SUBSCRIPTION_ID:-}"
AZURE_LOCATION="${AZURE_LOCATION:-westeurope}"
GITHUB_REPO="${GITHUB_REPOSITORY:-}"
TERRAFORM_STATE_RG="${TERRAFORM_STATE_RG:-rg-netbench-state-001}"
TERRAFORM_STATE_SA="${TERRAFORM_STATE_SA:-sanetbenchstate001}"
TERRAFORM_STATE_CONTAINER="${TERRAFORM_STATE_CONTAINER:-tfstate}"
WEBAPP_RG="${WEBAPP_RG:-rg-netbench-dashboard-001}"
WEBAPP_SA="${WEBAPP_SA:-sanetbenchdashboard001}"
SP_NAME="${SP_NAME:-azure-netbench-sp-$(date +%s)}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --state-subscription-id)
            TERRAFORM_STATE_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --location)
            AZURE_LOCATION="$2"
            shift 2
            ;;
        --repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        --state-rg)
            TERRAFORM_STATE_RG="$2"
            shift 2
            ;;
        --state-sa)
            TERRAFORM_STATE_SA="$2"
            shift 2
            ;;
        --state-container)
            TERRAFORM_STATE_CONTAINER="$2"
            shift 2
            ;;
        --webapp-rg)
            WEBAPP_RG="$2"
            shift 2
            ;;
        --webapp-sa)
            WEBAPP_SA="$2"
            shift 2
            ;;
        --sp-name)
            SP_NAME="$2"
            shift 2
            ;;
        -y|--yes)
            NON_INTERACTIVE="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

echo "=== GitHub Secrets Setup for Azure Network Benchmark ==="
echo

for required_cmd in gh az jq; do
    if ! command -v "$required_cmd" &> /dev/null; then
        echo "Error: '$required_cmd' CLI is required but not installed." >&2
        exit 1
    fi
done

if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub CLI. Run 'gh auth login'." >&2
    exit 1
fi

if ! az account show &> /dev/null; then
    echo "Error: Not authenticated with Azure CLI. Run 'az login'." >&2
    exit 1
fi

if [[ -z "$GITHUB_REPO" ]]; then
    GITHUB_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "jonathan-vella/azure-networking")
fi

if [[ -z "$SUBSCRIPTION_ID" ]]; then
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
fi

echo "Configuration:"
echo "  GitHub Repository:   $GITHUB_REPO"
echo "  Azure Subscription:  $SUBSCRIPTION_ID"
echo "  Default Location:    $AZURE_LOCATION"

if [[ "$NON_INTERACTIVE" != "true" ]]; then
    read -r -p "Use Azure subscription '$SUBSCRIPTION_ID' and repository '$GITHUB_REPO'? (y/N): " REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        read -r -p "Enter Azure subscription ID [$SUBSCRIPTION_ID]: " INPUT_SUB
        SUBSCRIPTION_ID="${INPUT_SUB:-$SUBSCRIPTION_ID}"
        read -r -p "Enter GitHub repository [$GITHUB_REPO]: " INPUT_REPO
        GITHUB_REPO="${INPUT_REPO:-$GITHUB_REPO}"
    fi
fi

if [[ -z "$TERRAFORM_STATE_SUBSCRIPTION_ID" ]]; then
    TERRAFORM_STATE_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
fi

if [[ "$NON_INTERACTIVE" != "true" ]]; then
    echo
    echo "Terraform backend & dashboard defaults:"
    echo "  State RG / SA / Container: $TERRAFORM_STATE_RG / $TERRAFORM_STATE_SA / $TERRAFORM_STATE_CONTAINER"
    echo "  State Subscription ID:     $TERRAFORM_STATE_SUBSCRIPTION_ID"
    echo "  Dashboard RG / SA:         $WEBAPP_RG / $WEBAPP_SA"
    read -r -p "Customize resource group or storage account names? (y/N): " REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        read -r -p "Terraform state subscription ID [$TERRAFORM_STATE_SUBSCRIPTION_ID]: " INPUT_VAL
        TERRAFORM_STATE_SUBSCRIPTION_ID="${INPUT_VAL:-$TERRAFORM_STATE_SUBSCRIPTION_ID}"
        read -r -p "Terraform state resource group [$TERRAFORM_STATE_RG]: " INPUT_VAL
        TERRAFORM_STATE_RG="${INPUT_VAL:-$TERRAFORM_STATE_RG}"
        read -r -p "Terraform state storage account [$TERRAFORM_STATE_SA]: " INPUT_VAL
        TERRAFORM_STATE_SA="${INPUT_VAL:-$TERRAFORM_STATE_SA}"
        read -r -p "Terraform state container [$TERRAFORM_STATE_CONTAINER]: " INPUT_VAL
        TERRAFORM_STATE_CONTAINER="${INPUT_VAL:-$TERRAFORM_STATE_CONTAINER}"
        read -r -p "Dashboard resource group [$WEBAPP_RG]: " INPUT_VAL
        WEBAPP_RG="${INPUT_VAL:-$WEBAPP_RG}"
        read -r -p "Dashboard storage account [$WEBAPP_SA]: " INPUT_VAL
        WEBAPP_SA="${INPUT_VAL:-$WEBAPP_SA}"
    fi
fi

echo
echo "Creating Azure service principal '$SP_NAME'..."
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "$SP_NAME" \
    --role "Contributor" \
    --scopes "/subscriptions/$SUBSCRIPTION_ID" \
    --output json)

CLIENT_ID=$(printf '%s' "$SP_OUTPUT" | jq -r '.appId')
CLIENT_SECRET=$(printf '%s' "$SP_OUTPUT" | jq -r '.password')
TENANT_ID=$(printf '%s' "$SP_OUTPUT" | jq -r '.tenant')

az role assignment create \
    --assignee "$CLIENT_ID" \
    --role "Role Based Access Control Administrator" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --output none

echo "Service principal created (Client ID: $CLIENT_ID, Tenant ID: $TENANT_ID)."
echo
echo "Configuring GitHub secrets on $GITHUB_REPO..."

gh secret set AZURE_SUBSCRIPTION_ID --repo "$GITHUB_REPO" --body "$SUBSCRIPTION_ID"
gh secret set AZURE_CLIENT_ID --repo "$GITHUB_REPO" --body "$CLIENT_ID"
gh secret set AZURE_CLIENT_SECRET --repo "$GITHUB_REPO" --body "$CLIENT_SECRET"
gh secret set AZURE_TENANT_ID --repo "$GITHUB_REPO" --body "$TENANT_ID"
gh secret set TERRAFORM_STATE_RG --repo "$GITHUB_REPO" --body "$TERRAFORM_STATE_RG"
gh secret set TERRAFORM_STATE_SA --repo "$GITHUB_REPO" --body "$TERRAFORM_STATE_SA"
gh secret set TERRAFORM_STATE_CONTAINER --repo "$GITHUB_REPO" --body "$TERRAFORM_STATE_CONTAINER"
gh secret set TERRAFORM_STATE_SUBSCRIPTION_ID --repo "$GITHUB_REPO" --body "$TERRAFORM_STATE_SUBSCRIPTION_ID"
gh secret set WEBAPP_RG --repo "$GITHUB_REPO" --body "$WEBAPP_RG"
gh secret set WEBAPP_SA --repo "$GITHUB_REPO" --body "$WEBAPP_SA"

echo "All GitHub secrets have been configured on $GITHUB_REPO."
echo
echo "Next steps (if storage resources do not exist yet):"
echo "  1. Create Terraform state & benchmark Table Storage account:"
echo "     az group create --name '$TERRAFORM_STATE_RG' --location '$AZURE_LOCATION'"
echo "     az storage account create --name '$TERRAFORM_STATE_SA' --resource-group '$TERRAFORM_STATE_RG' --location '$AZURE_LOCATION' --sku Standard_LRS"
echo "     az storage container create --name '$TERRAFORM_STATE_CONTAINER' --account-name '$TERRAFORM_STATE_SA' --auth-mode login"
echo "     az storage table create --name 'perf' --account-name '$TERRAFORM_STATE_SA' --auth-mode login"
echo
echo "  2. Run a benchmark for any region in tools/netbench:"
echo "     terraform init"
echo "     terraform apply -var='location=$AZURE_LOCATION' -var='storage_account_name=$TERRAFORM_STATE_SA' -var='storage_account_resource_group=$TERRAFORM_STATE_RG'"

