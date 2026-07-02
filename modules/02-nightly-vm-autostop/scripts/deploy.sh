#!/usr/bin/env bash
set -euo pipefail

# Run this script from Git Bash.
# Prevent Git Bash from converting Azure resource IDs such as /subscriptions/... into local paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LOC="westeurope"
TIMEZONE="Europe/Berlin"
AUTOMATION_API_VERSION="2024-10-23"

# Control plane
RG_OPS="rg-ops-guardrails"
AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
SCHEDULE_NAME="sched-stop-vms-0200"

# Target scope
RG_FINOPS_LAB="rg-finops-lab"

# Least-privilege RBAC
ROLE_NAME="FinOps VM AutoStop Operator"

RUNBOOK_FILE="$MODULE_DIR/infra/stop-tagged-vms.ps1"
ROLE_TEMPLATE="$MODULE_DIR/infra/finops-vm-autostop-role.json"

# Azure CLI runs natively on Windows. File references therefore need Windows paths.
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
LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "Creating resource groups..."
az group create --name "$RG_OPS" --location "$LOC" -o none
az group create --name "$RG_FINOPS_LAB" --location "$LOC" -o none

echo "Creating or validating Automation Account..."
if ! az automation account show \
  --resource-group "$RG_OPS" \
  --name "$AA_NAME" \
  -o none 2>/dev/null; then

  az automation account create \
    --resource-group "$RG_OPS" \
    --name "$AA_NAME" \
    --location "$LOC" \
    -o none
fi

AA_ID=$(az automation account show \
  --resource-group "$RG_OPS" \
  --name "$AA_NAME" \
  --query id \
  -o tsv)

echo "Enabling system-assigned managed identity..."
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

  [[ -n "$PRINCIPAL_ID" ]] && break
  sleep 5
done

[[ -n "$PRINCIPAL_ID" ]] || {
  echo "ERROR: Managed Identity principalId was not available."
  exit 1
}

echo "Managed Identity Principal ID: $PRINCIPAL_ID"

# Render the portable role template with the current subscription-specific scope.
ROLE_RENDERED_FILE=$(mktemp)
ROLE_RENDERED_FILE_AZ="@$(cygpath -w "$ROLE_RENDERED_FILE")"

trap 'rm -f "$ROLE_RENDERED_FILE"' EXIT

sed "s|__LAB_SCOPE__|$LAB_SCOPE|g" \
  "$ROLE_TEMPLATE" > "$ROLE_RENDERED_FILE"

ROLE_DEFINITION_ID=$(az role definition list \
  --name "$ROLE_NAME" \
  --custom-role-only true \
  --query "[0].id" \
  -o tsv 2>/dev/null || true)

if [[ -z "$ROLE_DEFINITION_ID" || "$ROLE_DEFINITION_ID" == "null" ]]; then
  echo "Creating custom role: $ROLE_NAME"

  az role definition create \
    --role-definition "$ROLE_RENDERED_FILE_AZ" \
    -o none
else
  echo "Custom role already exists: $ROLE_NAME"
  echo "Skipping role-definition update."
fi

CUSTOM_ASSIGNMENT_ID=$(az_no_pathconv role assignment list \
  --assignee-object-id "$PRINCIPAL_ID" \
  --role "$ROLE_NAME" \
  --scope "$LAB_SCOPE" \
  --query "[0].id" \
  -o tsv 2>/dev/null || true)

if [[ -z "$CUSTOM_ASSIGNMENT_ID" || "$CUSTOM_ASSIGNMENT_ID" == "null" ]]; then
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

echo "Creating or updating runbook..."
if ! az automation runbook show \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  -o none 2>/dev/null; then

  az automation runbook create \
    --resource-group "$RG_OPS" \
    --automation-account-name "$AA_NAME" \
    --name "$RUNBOOK_NAME" \
    --type PowerShell \
    --location "$LOC" \
    -o none
fi

az automation runbook replace-content \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  --content "$RUNBOOK_FILE_AZ" \
  -o none

az automation runbook publish \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  -o none

NEXT_0200=$(TZ="$TIMEZONE" date -d "tomorrow 02:00" "+%Y-%m-%dT%H:%M:%S%:z")

if az automation schedule show \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$SCHEDULE_NAME" \
  -o none 2>/dev/null; then

  echo "Schedule already exists: $SCHEDULE_NAME"
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
fi

# Job schedules connect a runbook to an Automation schedule.
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
    echo "ERROR: Could not create the Runbook-to-schedule link."
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
echo "Runbook Schedule: $SCHEDULE_NAME"
echo
echo "NOTE:"
echo "This script does not create, update, or remove legacy subscription-level role assignments."