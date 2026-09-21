#!/usr/bin/env bash
set -euo pipefail

# Run this script from Git Bash.
# Prevent Git Bash from converting Azure resource IDs such as
# /subscriptions/... into local Windows paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LOC="westeurope"
TIMEZONE="Europe/Berlin"
AUTOMATION_API_VERSION="2024-10-23"

# Shared Foundation scopes.
# Module 02 consumes these Resource Groups but does not own them.
RG_OPS="rg-ops-guardrails"
RG_FINOPS_LAB="rg-finops-lab"

# Module 02 resources.
AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
SCHEDULE_NAME="sched-stop-vms-0200"

# Least-privilege RBAC.
ROLE_NAME="FinOps VM AutoStop Operator"

RUNBOOK_FILE="$MODULE_DIR/infra/stop-tagged-vms.ps1"
ROLE_TEMPLATE="$MODULE_DIR/infra/finops-vm-autostop-role.json"

# Azure CLI runs natively on Windows.
# File references therefore need Windows paths.
RUNBOOK_FILE_AZ="@$(cygpath -w "$RUNBOOK_FILE")"

[[ -f "$RUNBOOK_FILE" ]] || {
  echo "ERROR: Runbook file not found: $RUNBOOK_FILE"
  exit 1
}

[[ -f "$ROLE_TEMPLATE" ]] || {
  echo "ERROR: Role definition file not found: $ROLE_TEMPLATE"
  exit 1
}

grep -q "__LAB_SCOPE__" "$ROLE_TEMPLATE" || {
  echo "ERROR: Role template must contain __LAB_SCOPE__ in AssignableScopes."
  exit 1
}

SUB_ID=$(az account show --query id -o tsv)

[[ -n "$SUB_ID" ]] || {
  echo "ERROR: No active Azure subscription found."
  exit 1
}

LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "Subscription: $SUB_ID"
echo

# -------------------------------------------------------------------
# Validate shared Foundation
# -------------------------------------------------------------------

echo "Validating shared Foundation Resource Groups..."

if ! az group show \
  --name "$RG_OPS" \
  -o none 2>/dev/null; then

  echo "ERROR: Shared Resource Group does not exist: $RG_OPS"
  echo "Module 02 does not own or create this Resource Group."
  exit 1
fi

echo "Found shared Resource Group: $RG_OPS"

if ! az group show \
  --name "$RG_FINOPS_LAB" \
  -o none 2>/dev/null; then

  echo "ERROR: Shared Resource Group does not exist: $RG_FINOPS_LAB"
  echo "Module 02 does not own or create this Resource Group."
  exit 1
fi

echo "Found shared Resource Group: $RG_FINOPS_LAB"
echo

# -------------------------------------------------------------------
# Automation Account + Managed Identity
# -------------------------------------------------------------------

echo "Creating or validating Automation Account..."

if ! az automation account show \
  --resource-group "$RG_OPS" \
  --name "$AA_NAME" \
  -o none 2>/dev/null; then

  echo "Creating Automation Account: $AA_NAME"

  az automation account create \
    --resource-group "$RG_OPS" \
    --name "$AA_NAME" \
    --location "$LOC" \
    -o none
else
  echo "Automation Account already exists: $AA_NAME"
fi

AA_ID=$(az automation account show \
  --resource-group "$RG_OPS" \
  --name "$AA_NAME" \
  --query id \
  -o tsv)

[[ -n "$AA_ID" ]] || {
  echo "ERROR: Could not resolve Automation Account resource ID."
  exit 1
}

echo "Enabling system-assigned Managed Identity..."

az_no_pathconv resource update \
  --ids "$AA_ID" \
  --set identity.type=SystemAssigned \
  -o none

PRINCIPAL_ID=""

for i in {1..24}; do
  PRINCIPAL_ID=$(az_no_pathconv resource show \
    --ids "$AA_ID" \
    --query identity.principalId \
    -o tsv 2>/dev/null || true)

  if [[ -n "$PRINCIPAL_ID" && "$PRINCIPAL_ID" != "null" ]]; then
    break
  fi

  sleep 5
done

[[ -n "$PRINCIPAL_ID" && "$PRINCIPAL_ID" != "null" ]] || {
  echo "ERROR: Managed Identity principalId was not available."
  exit 1
}

echo "Managed Identity Principal ID: $PRINCIPAL_ID"
echo

# -------------------------------------------------------------------
# Custom RBAC Role
# -------------------------------------------------------------------

echo "Rendering least-privilege custom role..."

ROLE_RENDERED_FILE=""
ROLE_UPDATE_FILE=""

cleanup_temp_files() {
  if [[ -n "$ROLE_RENDERED_FILE" && -f "$ROLE_RENDERED_FILE" ]]; then
    rm -f "$ROLE_RENDERED_FILE"
  fi

  if [[ -n "$ROLE_UPDATE_FILE" && -f "$ROLE_UPDATE_FILE" ]]; then
    rm -f "$ROLE_UPDATE_FILE"
  fi
}

trap cleanup_temp_files EXIT

ROLE_RENDERED_FILE=$(mktemp)
ROLE_RENDERED_FILE_AZ="@$(cygpath -w "$ROLE_RENDERED_FILE")"

sed "s|__LAB_SCOPE__|$LAB_SCOPE|g" \
  "$ROLE_TEMPLATE" > "$ROLE_RENDERED_FILE"

ROLE_DEFINITION_ID=$(az role definition list \
  --name "$ROLE_NAME" \
  --custom-role-only true \
  --query "[0].id" \
  -o tsv)

if [[ -z "$ROLE_DEFINITION_ID" || "$ROLE_DEFINITION_ID" == "null" ]]; then

  echo "Creating custom role: $ROLE_NAME"

  az role definition create \
    --role-definition "$ROLE_RENDERED_FILE_AZ" \
    -o none

else

  echo "Custom role already exists: $ROLE_NAME"
  echo "Reconciling custom role with repository definition..."

  ROLE_DEFINITION_GUID="${ROLE_DEFINITION_ID##*/}"

  [[ -n "$ROLE_DEFINITION_GUID" ]] || {
    echo "ERROR: Could not extract custom role definition GUID."
    exit 1
  }

  ROLE_UPDATE_FILE=$(mktemp)
  ROLE_UPDATE_FILE_AZ="@$(cygpath -w "$ROLE_UPDATE_FILE")"

  # Pass only GUID values to Windows Python.
  # Full Azure resource IDs beginning with /subscriptions/... are otherwise
  # rewritten by Git Bash/MSYS path conversion.
  python3 - \
    "$ROLE_RENDERED_FILE" \
    "$ROLE_UPDATE_FILE" \
    "$SUB_ID" \
    "$ROLE_DEFINITION_GUID" <<'PY'
import json
import sys

source_file = sys.argv[1]
target_file = sys.argv[2]
subscription_id = sys.argv[3]
role_guid = sys.argv[4]

with open(source_file, "r", encoding="utf-8") as f:
    role = json.load(f)

role_resource_id = (
    f"/subscriptions/{subscription_id}"
    f"/providers/Microsoft.Authorization/roleDefinitions/{role_guid}"
)

update_role = {
    "roleName": role["Name"],
    "id": role_resource_id,
    "description": role.get("Description"),
    "actions": role.get("Actions", []),
    "notActions": role.get("NotActions", []),
    "dataActions": role.get("DataActions", []),
    "notDataActions": role.get("NotDataActions", []),
    "assignableScopes": role.get("AssignableScopes", [])
}

with open(target_file, "w", encoding="utf-8") as f:
    json.dump(update_role, f, indent=2)
    f.write("\n")
PY

  az role definition update \
    --role-definition "$ROLE_UPDATE_FILE_AZ" \
    -o none
fi

echo "Validating custom role..."

ROLE_SCOPE=$(az role definition list \
  --name "$ROLE_NAME" \
  --custom-role-only true \
  --query "[0].assignableScopes[0]" \
  -o tsv)

[[ "$ROLE_SCOPE" == "$LAB_SCOPE" ]] || {
  echo "ERROR: Custom role has unexpected AssignableScope."
  echo "Expected: $LAB_SCOPE"
  echo "Actual:   $ROLE_SCOPE"
  exit 1
}

ROLE_ACTIONS=$(az role definition list \
  --name "$ROLE_NAME" \
  --custom-role-only true \
  --query "[0].permissions[0].actions[]" \
  -o tsv)

REQUIRED_ACTIONS=(
  "Microsoft.Compute/virtualMachines/read"
  "Microsoft.Compute/virtualMachines/instanceView/read"
  "Microsoft.Compute/virtualMachines/deallocate/action"
)

for ACTION in "${REQUIRED_ACTIONS[@]}"; do
  if ! grep -Fxq "$ACTION" <<< "$ROLE_ACTIONS"; then
    echo "ERROR: Required action missing from custom role:"
    echo "$ACTION"
    exit 1
  fi
done

echo "Custom role validated."
echo

# -------------------------------------------------------------------
# Managed Identity RBAC Assignment
# -------------------------------------------------------------------

echo "Validating Managed Identity role assignment..."

CUSTOM_ASSIGNMENT_ID=$(az_no_pathconv role assignment list \
  --assignee-object-id "$PRINCIPAL_ID" \
  --role "$ROLE_NAME" \
  --scope "$LAB_SCOPE" \
  --query "[0].id" \
  -o tsv)

if [[ -z "$CUSTOM_ASSIGNMENT_ID" || "$CUSTOM_ASSIGNMENT_ID" == "null" ]]; then

  echo "Role assignment missing."
  echo "Assigning custom role at Resource Group scope..."

  az_no_pathconv role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "$ROLE_NAME" \
    --scope "$LAB_SCOPE" \
    -o none
else
  echo "Custom role assignment already exists."
fi

echo "Confirming role assignment..."

CONFIRMED_ASSIGNMENT_ID=""

for i in {1..12}; do
  CONFIRMED_ASSIGNMENT_ID=$(az_no_pathconv role assignment list \
    --assignee-object-id "$PRINCIPAL_ID" \
    --role "$ROLE_NAME" \
    --scope "$LAB_SCOPE" \
    --query "[0].id" \
    -o tsv 2>/dev/null || true)

  if [[ -n "$CONFIRMED_ASSIGNMENT_ID" && "$CONFIRMED_ASSIGNMENT_ID" != "null" ]]; then
    break
  fi

  sleep 5
done

[[ -n "$CONFIRMED_ASSIGNMENT_ID" && "$CONFIRMED_ASSIGNMENT_ID" != "null" ]] || {
  echo "ERROR: Custom role assignment could not be confirmed."
  exit 1
}

echo "Role assignment confirmed:"
echo "$CONFIRMED_ASSIGNMENT_ID"
echo

# -------------------------------------------------------------------
# Runbook
# -------------------------------------------------------------------

echo "Creating or updating runbook..."

if ! az automation runbook show \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  -o none 2>/dev/null; then

  echo "Creating runbook: $RUNBOOK_NAME"

  az automation runbook create \
    --resource-group "$RG_OPS" \
    --automation-account-name "$AA_NAME" \
    --name "$RUNBOOK_NAME" \
    --type PowerShell \
    --location "$LOC" \
    -o none
else
  echo "Runbook already exists: $RUNBOOK_NAME"
fi

echo "Replacing runbook content..."

az automation runbook replace-content \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  --content "$RUNBOOK_FILE_AZ" \
  -o none

echo "Publishing runbook..."

az automation runbook publish \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  -o none

# -------------------------------------------------------------------
# Schedule
# -------------------------------------------------------------------

NEXT_0200=$(TZ="$TIMEZONE" date -d "tomorrow 02:00" "+%Y-%m-%dT%H:%M:%S%:z")

if az automation schedule show \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$SCHEDULE_NAME" \
  -o none 2>/dev/null; then

  echo "Schedule already exists: $SCHEDULE_NAME"
  echo "Validating schedule configuration..."

  SCHEDULE_FREQUENCY=$(az automation schedule show \
    --resource-group "$RG_OPS" \
    --automation-account-name "$AA_NAME" \
    --name "$SCHEDULE_NAME" \
    --query frequency \
    -o tsv)

  SCHEDULE_INTERVAL=$(az automation schedule show \
    --resource-group "$RG_OPS" \
    --automation-account-name "$AA_NAME" \
    --name "$SCHEDULE_NAME" \
    --query interval \
    -o tsv)

  SCHEDULE_TIMEZONE=$(az automation schedule show \
    --resource-group "$RG_OPS" \
    --automation-account-name "$AA_NAME" \
    --name "$SCHEDULE_NAME" \
    --query timeZone \
    -o tsv)

  SCHEDULE_ENABLED=$(az automation schedule show \
    --resource-group "$RG_OPS" \
    --automation-account-name "$AA_NAME" \
    --name "$SCHEDULE_NAME" \
    --query isEnabled \
    -o tsv)

  if [[ "$SCHEDULE_FREQUENCY" != "Day" ]]; then
    echo "ERROR: Schedule frequency drift detected."
    echo "Expected: Day"
    echo "Actual:   $SCHEDULE_FREQUENCY"
    exit 1
  fi

  if [[ "$SCHEDULE_INTERVAL" != "1" ]]; then
    echo "ERROR: Schedule interval drift detected."
    echo "Expected: 1"
    echo "Actual:   $SCHEDULE_INTERVAL"
    exit 1
  fi

  if [[ "$SCHEDULE_TIMEZONE" != "$TIMEZONE" ]]; then
    echo "ERROR: Schedule timezone drift detected."
    echo "Expected: $TIMEZONE"
    echo "Actual:   $SCHEDULE_TIMEZONE"
    exit 1
  fi

  if [[ "${SCHEDULE_ENABLED,,}" != "true" ]]; then
    echo "ERROR: Schedule is disabled."
    exit 1
  fi

  echo "Schedule validated:"
  echo "- Frequency: $SCHEDULE_FREQUENCY"
  echo "- Interval: $SCHEDULE_INTERVAL"
  echo "- Time zone: $SCHEDULE_TIMEZONE"
  echo "- Enabled: $SCHEDULE_ENABLED"

else

  echo "Creating schedule: $SCHEDULE_NAME"

  az automation schedule create \
    --resource-group "$RG_OPS" \
    --automation-account-name "$AA_NAME" \
    --name "$SCHEDULE_NAME" \
    --frequency Day \
    --interval 1 \
    --start-time "$NEXT_0200" \
    --time-zone "$TIMEZONE" \
    -o none

  echo "Schedule created successfully."
fi

echo

# -------------------------------------------------------------------
# Runbook-to-Schedule Link
# -------------------------------------------------------------------

JOB_SCHEDULE_LIST_URL="https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Automation/automationAccounts/$AA_NAME/jobSchedules?api-version=$AUTOMATION_API_VERSION"

find_job_schedule() {
  az_no_pathconv rest \
    --method get \
    --url "$JOB_SCHEDULE_LIST_URL" \
    --query "value[?properties.runbook.name=='$RUNBOOK_NAME' && properties.schedule.name=='$SCHEDULE_NAME'].properties.jobScheduleId | [0]" \
    -o tsv 2>/dev/null || true
}

EXISTING_JOB_SCHEDULE_ID=$(find_job_schedule)

if [[ -n "$EXISTING_JOB_SCHEDULE_ID" && "$EXISTING_JOB_SCHEDULE_ID" != "null" ]]; then

  echo "Job schedule link already exists: $EXISTING_JOB_SCHEDULE_ID"

else

  JOB_SCHEDULE_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')

  JOB_SCHEDULE_URL="https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Automation/automationAccounts/$AA_NAME/jobSchedules/$JOB_SCHEDULE_ID?api-version=$AUTOMATION_API_VERSION"

  BODY=$(cat <<JSON
{
  "properties": {
    "runbook": {
      "name": "$RUNBOOK_NAME"
    },
    "schedule": {
      "name": "$SCHEDULE_NAME"
    }
  }
}
JSON
)

  echo "Creating job schedule link: $JOB_SCHEDULE_ID"

  if ! JOB_SCHEDULE_OUTPUT=$(
    az_no_pathconv rest \
      --method put \
      --url "$JOB_SCHEDULE_URL" \
      --headers "Content-Type=application/json" \
      --body "$BODY" \
      -o none 2>&1
  ); then

    echo "$JOB_SCHEDULE_OUTPUT"
    echo
    echo "ERROR: Could not create the Runbook-to-Schedule link."
    exit 1
  fi

  echo "Validating newly created job schedule link..."

  CONFIRMED_JOB_SCHEDULE_ID=""

  for i in {1..12}; do
    CONFIRMED_JOB_SCHEDULE_ID=$(find_job_schedule)

    if [[ -n "$CONFIRMED_JOB_SCHEDULE_ID" && "$CONFIRMED_JOB_SCHEDULE_ID" != "null" ]]; then
      break
    fi

    sleep 5
  done

  [[ -n "$CONFIRMED_JOB_SCHEDULE_ID" && "$CONFIRMED_JOB_SCHEDULE_ID" != "null" ]] || {
    echo "ERROR: Job schedule creation returned successfully, but the link could not be confirmed."
    exit 1
  }

  echo "Job schedule link confirmed: $CONFIRMED_JOB_SCHEDULE_ID"
fi

echo
echo "Deployment successful."
echo "Automation Account: $AA_NAME"
echo "Managed Identity: $PRINCIPAL_ID"
echo "Custom Role: $ROLE_NAME"
echo "Custom Role Scope: $LAB_SCOPE"
echo "Role Assignment: $CONFIRMED_ASSIGNMENT_ID"
echo "Runbook Schedule: $SCHEDULE_NAME"
echo
echo "Shared Foundation preserved:"
echo "- $RG_OPS"
echo "- $RG_FINOPS_LAB"
echo
echo "NOTE:"
echo "This script does not create, delete, or take ownership of shared Resource Groups."
echo "This script does not create, update, or remove legacy subscription-level role assignments."
