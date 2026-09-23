#!/usr/bin/env bash
set -euo pipefail

# Run this script from Git Bash.
# Prevent Git Bash/MSYS from converting Azure resource IDs into local Windows paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

RG_FINOPS_LAB="rg-finops-lab"

ASSIGNMENTS=(
  "inherit-environment-tag"
  "inherit-project-tag"
  "inherit-costcenter-tag"
  "inherit-owner-tag"
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

if ! az group show \
  --name "$RG_FINOPS_LAB" \
  -o none; then
  echo "ERROR: Shared Foundation Resource Group not found: $RG_FINOPS_LAB"
  echo "Module 03 cleanup will not attempt to recreate or delete Foundation resources."
  exit 1
fi

echo "Found shared Resource Group: $RG_FINOPS_LAB"

for ASSIGNMENT_NAME in "${ASSIGNMENTS[@]}"; do
  echo
  echo "Processing Module 03 policy assignment: $ASSIGNMENT_NAME"

  EXISTING_NAME=$(az_no_pathconv policy assignment list \
    --scope "$LAB_SCOPE" \
    --query "[?name=='$ASSIGNMENT_NAME'].name | [0]" \
    -o tsv)

  if [[ -z "$EXISTING_NAME" || "$EXISTING_NAME" == "null" ]]; then
    echo "Policy assignment not present. Nothing to remove."
    continue
  fi

  PRINCIPAL_ID=$(az_no_pathconv policy assignment show \
    --name "$ASSIGNMENT_NAME" \
    --scope "$LAB_SCOPE" \
    --query identity.principalId \
    -o tsv)

  if [[ -n "$PRINCIPAL_ID" && "$PRINCIPAL_ID" != "null" ]]; then
    ROLE_ASSIGNMENT_ID=$(az_no_pathconv role assignment list \
      --role "Tag Contributor" \
      --scope "$LAB_SCOPE" \
      --query "[?principalId=='$PRINCIPAL_ID' && scope=='$LAB_SCOPE'].id | [0]" \
      -o tsv)

    if [[ -n "$ROLE_ASSIGNMENT_ID" && "$ROLE_ASSIGNMENT_ID" != "null" ]]; then
      echo "Removing Tag Contributor role assignment..."
      az_no_pathconv role assignment delete \
        --ids "$ROLE_ASSIGNMENT_ID"
      echo "Role assignment removed."
    else
      echo "No Module 03 Tag Contributor role assignment found for this identity."
    fi
  else
    echo "No Managed Identity principalId found on assignment."
  fi

  echo "Removing policy assignment..."
  az_no_pathconv policy assignment delete \
    --name "$ASSIGNMENT_NAME" \
    --scope "$LAB_SCOPE"
  echo "Policy assignment removed."
done

echo
echo "Cleanup complete."
echo
echo "Shared Foundation preserved:"
echo "- Resource Group: $RG_FINOPS_LAB"
echo "- Resource Group governance tags"
echo "- unrelated policy assignments, including Module 04"
echo "- built-in Azure Policy definition"
