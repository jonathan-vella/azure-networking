#!/usr/bin/env bash
set -euo pipefail

SUBSCRIPTION_ID="${1:-${AZURE_SUBSCRIPTION_ID:-}}"
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || true)
fi

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "Usage: $0 <subscription-id>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RESPONSE="$(az rest \
  --method get \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/locations?api-version=2022-12-01" \
  --query 'value[?availabilityZoneMappings != `null`].{displayName: displayName, name: name, availabilityZoneMappings: availabilityZoneMappings}' \
  --output json)"

if [[ -z "$RESPONSE" ]]; then
  echo "Error: empty response from Azure Resource Manager Locations API." >&2
  exit 1
fi

printf '%s\n' "$RESPONSE" > "${SCRIPT_DIR}/availabilityZoneMappings.json"
