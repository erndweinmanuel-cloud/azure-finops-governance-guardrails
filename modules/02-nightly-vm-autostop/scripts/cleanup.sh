#!/usr/bin/env bash
set -euo pipefail

# Run this script from Git Bash.
# Prevent Git Bash from converting Azure resource IDs such as
# /subscriptions/... into local Windows paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

# Shared Foundation scopes.
# Module 02 consumes these Resource Groups but never owns or deletes them.
RG_OPS="rg-ops-guardrails"
RG_FINOPS_LAB="rg-finops-lab"

# Module 02 resources.
AA_NAME="aa-ops-guardrails"
ROLE_NAME="FinOps VM AutoStop Operator"

SUB_ID=$(az account show --query id -o tsv)

[[ -n "$SUB_ID" ]] || {
  echo "ERROR: No active Azure subscription found."
  exit 1
}

SUBSCRIPTION_SCOPE="/subscriptions/$SUB_ID"
LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "WARNING: This cleanup removes Module 02-owned resources only:"
echo "- Automation Account: $AA_NAME"
echo "  (including its runbook, schedule, and job-schedule links)"
echo "- Module 02 Managed Identity role assignments"
echo "- Custom role definition: $ROLE_NAME"
echo
echo "The following shared Foundation Resource Groups will be preserved:"
echo "- $RG_OPS"
echo "- $RG_FINOPS_LAB"
echo

read -r -p "Type DELETE to continue: " CONFIRM

if [[ "$CONFIRM" != "DELETE" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo
echo "Discovering Module 02 Automation Account..."

AA_ID=$(az resource list \
  --resource-group "$RG_OPS" \
  --resource-type "Microsoft.Automation/automationAccounts" \
  --query "[?name=='$AA_NAME'].id | [0]" \
  -o tsv)

PRINCIPAL_ID=""

if [[ -n "$AA_ID" && "$AA_ID" != "null" ]]; then
  echo "Found Automation Account: $AA_NAME"

  PRINCIPAL_ID=$(az_no_pathconv resource show \
    --ids "$AA_ID" \
    --query identity.principalId \
    -o tsv)

  if [[ "$PRINCIPAL_ID" == "null" ]]; then
    PRINCIPAL_ID=""
  fi

  echo "Managed Identity Principal ID: ${PRINCIPAL_ID:-not found}"
else
  echo "Automation Account not found. Skipping Managed Identity lookup."
fi

if [[ -n "$PRINCIPAL_ID" ]]; then
  echo
  echo "Checking Module 02 custom-role assignment..."

  CUSTOM_ASSIGNMENT_ID=$(az_no_pathconv role assignment list \
    --assignee-object-id "$PRINCIPAL_ID" \
    --role "$ROLE_NAME" \
    --scope "$LAB_SCOPE" \
    --query "[?scope=='$LAB_SCOPE'].id | [0]" \
    -o tsv)

  if [[ -n "$CUSTOM_ASSIGNMENT_ID" && "$CUSTOM_ASSIGNMENT_ID" != "null" ]]; then
    echo "Removing custom-role assignment from $RG_FINOPS_LAB..."

    az_no_pathconv role assignment delete \
      --ids "$CUSTOM_ASSIGNMENT_ID"
  else
    echo "Custom-role assignment not found. Nothing to remove."
  fi

  echo
  echo "Checking legacy subscription-level Virtual Machine Contributor assignment..."

  LEGACY_ASSIGNMENT_ID=$(az_no_pathconv role assignment list \
    --assignee-object-id "$PRINCIPAL_ID" \
    --role "Virtual Machine Contributor" \
    --scope "$SUBSCRIPTION_SCOPE" \
    --query "[?scope=='$SUBSCRIPTION_SCOPE'].id | [0]" \
    -o tsv)

  if [[ -n "$LEGACY_ASSIGNMENT_ID" && "$LEGACY_ASSIGNMENT_ID" != "null" ]]; then
    echo "Removing legacy subscription-level Virtual Machine Contributor assignment..."

    az_no_pathconv role assignment delete \
      --ids "$LEGACY_ASSIGNMENT_ID"
  else
    echo "Legacy subscription-level assignment not found. Nothing to remove."
  fi
fi

echo
if [[ -n "$AA_ID" && "$AA_ID" != "null" ]]; then
  echo "Removing Automation Account and contained Module 02 Automation resources..."

  az automation account delete \
    --resource-group "$RG_OPS" \
    --name "$AA_NAME" \
    --yes \
    -o none
else
  echo "Automation Account already absent. Nothing to remove."
fi

echo
echo "Checking Module 02 custom role definition..."

ROLE_DEFINITION_ID=$(az role definition list \
  --name "$ROLE_NAME" \
  --custom-role-only true \
  --query "[0].id" \
  -o tsv)

if [[ -n "$ROLE_DEFINITION_ID" && "$ROLE_DEFINITION_ID" != "null" ]]; then
  ROLE_DEFINITION_GUID="${ROLE_DEFINITION_ID##*/}"

  [[ -n "$ROLE_DEFINITION_GUID" ]] || {
    echo "ERROR: Could not extract custom role definition GUID."
    exit 1
  }

  echo "Removing custom role definition: $ROLE_NAME"

  az role definition delete \
    --name "$ROLE_DEFINITION_GUID"
else
  echo "Custom role definition already absent. Nothing to remove."
fi

echo
echo "Keeping shared Foundation Resource Group: $RG_OPS"
echo "Keeping shared Foundation Resource Group: $RG_FINOPS_LAB"
echo
echo "Module 02 cleanup completed."
echo "Shared Foundation Resource Groups were preserved."
