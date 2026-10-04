#!/usr/bin/env bash
set -euo pipefail

az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

RG_FINOPS_LAB="rg-finops-lab"

POLICY_ASSIGNMENTS=(
  "allowed-vm-sizes"
  "deny-public-ip"
  "require-autostop-tag"
  "audit-governance-tags"
)

POLICY_DEFINITIONS=(
  "finops-allowed-vm-sizes"
  "finops-deny-public-ip"
  "finops-require-vm-autostop"
  "finops-audit-governance-tags"
)

SUB_ID=$(az account show --query id -o tsv)

[[ -n "$SUB_ID" ]] || {
  echo "ERROR: No active Azure subscription found."
  exit 1
}

LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "Subscription: $SUB_ID"
echo "Scope: $LAB_SCOPE"
echo
echo "Validating shared Foundation Resource Group..."

if ! az group show --name "$RG_FINOPS_LAB" -o none; then
  echo "ERROR: Shared Foundation Resource Group not found: $RG_FINOPS_LAB"
  echo "Module 04 cleanup will not recreate or delete Foundation resources."
  exit 1
fi

echo "Found shared Resource Group: $RG_FINOPS_LAB"

echo
echo "Removing Module 04 policy assignments..."

for assignment in "${POLICY_ASSIGNMENTS[@]}"; do
  existing_name=$(az_no_pathconv policy assignment list \
    --scope "$LAB_SCOPE" \
    --query "[?name=='$assignment'].name | [0]" \
    -o tsv)

  if [[ -z "$existing_name" || "$existing_name" == "null" ]]; then
    echo "Policy assignment not present, skipping: $assignment"
    continue
  fi

  az_no_pathconv policy assignment delete \
    --name "$assignment" \
    --scope "$LAB_SCOPE"

  echo "Deleted policy assignment: $assignment"
done

echo
echo "Removing Module 04 custom policy definitions..."

for definition in "${POLICY_DEFINITIONS[@]}"; do
  existing_name=$(az policy definition list \
    --query "[?name=='$definition'].name | [0]" \
    -o tsv)

  if [[ -z "$existing_name" || "$existing_name" == "null" ]]; then
    echo "Policy definition not present, skipping: $definition"
    continue
  fi

  az policy definition delete \
    --name "$definition"

  echo "Deleted policy definition: $definition"
done

echo
echo "Cleanup complete."
echo
echo "Shared Foundation preserved:"
echo "- Resource Group: $RG_FINOPS_LAB"
echo "- Foundation governance tags"
echo "- Module 03 tag inheritance assignments"
echo "- unrelated resources and assignments in the shared lab scope"
