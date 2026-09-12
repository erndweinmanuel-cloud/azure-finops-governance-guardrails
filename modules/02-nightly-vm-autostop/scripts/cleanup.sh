#!/usr/bin/env bash
set -euo pipefail

# Run this script from Git Bash.
# Prevent Git Bash from converting Azure resource IDs such as
# /subscriptions/... into local Windows paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

# Shared control-plane resource group.
# Module 02 consumes resources in this scope but does not own the Resource Group.
RG_OPS="rg-ops-guardrails"

# Shared FinOps lab resource group.
# Module 02 uses this as its AutoStop target scope but must never delete it.
RG_FINOPS_LAB="rg-finops-lab"

AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
SCHEDULE_NAME="sched-stop-vms-0200"

ROLE_NAME="FinOps VM AutoStop Operator"

SUB_ID=$(az account show --query id -o tsv)

SUBSCRIPTION_SCOPE="/subscriptions/$SUB_ID"
LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "WARNING: This cleanup removes Module 02 resources only:"
echo "- Automation Account: $AA_NAME"
echo "- Runbook: $RUNBOOK_NAME"
echo "- Schedule: $SCHEDULE_NAME"
echo "- Module 02 Managed Identity role assignments"
echo "- Custom role definition: $ROLE_NAME"
echo
echo "The following shared Resource Groups will be preserved:"
echo "- $RG_OPS"
echo "- $RG_FINOPS_LAB"
echo

read -r -p "Type DELETE to continue: " CONFIRM

if [[ "$CONFIRM" != "DELETE" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Read the Managed Identity before deleting the Automation Account.
PRINCIPAL_ID=$(az automation account show \
  --resource-group "$RG_OPS" \
  --name "$AA_NAME" \
  --query identity.principalId \
  -o tsv 2>/dev/null || true)

echo "Managed Identity Principal ID: ${PRINCIPAL_ID:-not found}"

if [[ -n "${PRINCIPAL_ID:-}" ]]; then
  echo "Removing Module 02 custom-role assignment from $RG_FINOPS_LAB..."

  az_no_pathconv role assignment delete \
    --assignee-object-id "$PRINCIPAL_ID" \
    --role "$ROLE_NAME" \
    --scope "$LAB_SCOPE" \
    -o none 2>/dev/null || true

  # Safety cleanup for old V1 deployments.
  # This only removes a legacy broad assignment if one still exists.
  echo "Removing legacy subscription-level Virtual Machine Contributor assignment..."

  az_no_pathconv role assignment delete \
    --assignee-object-id "$PRINCIPAL_ID" \
    --role "Virtual Machine Contributor" \
    --scope "$SUBSCRIPTION_SCOPE" \
    -o none 2>/dev/null || true
fi

# Deleting the Automation Account also removes its runbooks,
# schedules and runbook-to-schedule links.
echo "Removing Automation Account and contained Automation resources..."

az automation account delete \
  --resource-group "$RG_OPS" \
  --name "$AA_NAME" \
  --yes \
  -o none 2>/dev/null || true

echo "Removing Module 02 custom role definition..."

az role definition delete \
  --name "$ROLE_NAME" \
  -o none 2>/dev/null || true

echo
echo "Keeping shared Resource Group: $RG_OPS"
echo "Keeping shared Resource Group: $RG_FINOPS_LAB"
echo
echo "Module 02 cleanup completed."
echo "Shared platform Resource Groups were preserved."
