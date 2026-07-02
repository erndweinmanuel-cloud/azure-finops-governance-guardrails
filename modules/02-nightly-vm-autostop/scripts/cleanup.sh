#!/usr/bin/env bash
set -euo pipefail

# Run this script from Git Bash.
# Prevent Git Bash from converting Azure resource IDs such as /subscriptions/... into local paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

# Shared control-plane resource group.
# This must remain because it is also used by other FinOps modules.
RG_OPS="rg-ops-guardrails"

# Dedicated Module 02 test scope.
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
echo "- Managed Identity role assignments"
echo "- Custom role definition: $ROLE_NAME"
echo "- FinOps lab resource group: $RG_FINOPS_LAB"
echo
echo "The shared resource group '$RG_OPS' will be kept."
echo "Budget alerts and other FinOps modules in that Resource Group remain untouched."
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
  echo "Removing custom-role assignment from rg-finops-lab..."

  az_no_pathconv role assignment delete \
    --assignee-object-id "$PRINCIPAL_ID" \
    --role "$ROLE_NAME" \
    --scope "$LAB_SCOPE" \
    -o none 2>/dev/null || true

  # Safety cleanup for old V1 deployments.
  # This does not create a broad assignment; it only removes one if it still exists.
  echo "Removing legacy subscription-level Virtual Machine Contributor assignment..."

  az_no_pathconv role assignment delete \
    --assignee-object-id "$PRINCIPAL_ID" \
    --role "Virtual Machine Contributor" \
    --scope "$SUBSCRIPTION_SCOPE" \
    -o none 2>/dev/null || true
fi

# Deleting the Automation Account also removes its runbooks, schedules
# and runbook-to-schedule links.
echo "Removing Automation Account and contained Automation resources..."

az automation account delete \
  --resource-group "$RG_OPS" \
  --name "$AA_NAME" \
  --yes \
  -o none 2>/dev/null || true

echo "Removing custom role definition..."

az role definition delete \
  --name "$ROLE_NAME" \
  -o none 2>/dev/null || true

echo "Removing FinOps lab resource group and all test resources..."

az group delete \
  --name "$RG_FINOPS_LAB" \
  --yes \
  --no-wait \
  -o none 2>/dev/null || true

echo "Keeping shared resource group: $RG_OPS"
echo "Budget alerts and other shared FinOps resources remain available."

echo
echo "Cleanup initiated successfully."
echo "The deletion of $RG_FINOPS_LAB runs asynchronously."