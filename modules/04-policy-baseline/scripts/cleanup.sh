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
LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "Removing Module 04 policy assignments from scope: $LAB_SCOPE"

for assignment in "${POLICY_ASSIGNMENTS[@]}"; do
  if az_no_pathconv policy assignment show --name "$assignment" --scope "$LAB_SCOPE" -o none 2>/dev/null; then
    az_no_pathconv policy assignment delete --name "$assignment" --scope "$LAB_SCOPE"
    echo "Deleted assignment: $assignment"
  else
    echo "Assignment not found, skipping: $assignment"
  fi
done

echo "Removing Module 04 custom policy definitions..."

for definition in "${POLICY_DEFINITIONS[@]}"; do
  if az_no_pathconv policy definition show --name "$definition" -o none 2>/dev/null; then
    az_no_pathconv policy definition delete --name "$definition"
    echo "Deleted definition: $definition"
  else
    echo "Definition not found, skipping: $definition"
  fi
done

echo "Cleanup completed."
echo "Note: Resource group '$RG_FINOPS_LAB' was not deleted by this script."
