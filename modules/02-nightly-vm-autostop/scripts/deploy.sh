set -euo pipefail

LOC="westeurope"
RG_OPS="rg-ops-guardrails"

AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
SCHEDULE_NAME="sched-stop-vms-0200"
TIMEZONE="Europe/Berlin"

RUNBOOK_FILE="../infra/stop-tagged-vms.ps1"

az group create -n "$RG_OPS" -l "$LOC" -o none

az automation account create --resource-group "$RG_OPS" --name "$AA_NAME" --location "$LOC" -o none || true

AA_ID=$(az automation account show --resource-group "$RG_OPS" --name "$AA_NAME" --query id -o tsv)
az resource update --ids "$AA_ID" --set identity.type=SystemAssigned -o none

PRINCIPAL_ID=""
for i in {1..24}; do
  PRINCIPAL_ID=$(az resource show --ids "$AA_ID" --query identity.principalId -o tsv 2>/dev/null || true)
  [ -n "$PRINCIPAL_ID" ] && break
  sleep 5
done
[ -n "$PRINCIPAL_ID" ] || { echo "ERROR: Managed Identity principalId not available"; exit 1; }

SUB_ID=$(az account show --query id -o tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Virtual Machine Contributor" \
  --scope "/subscriptions/$SUB_ID" \
  -o none || true

az automation runbook create \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  --type PowerShell \
  --location "$LOC" \
  -o none || true

az automation runbook replace-content \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  --content "@$RUNBOOK_FILE" \
  -o none

az automation runbook publish \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  -o none

NEXT_0200=$(TZ="$TIMEZONE" date -d "tomorrow 02:00" "+%Y-%m-%dT%H:%M:%S%:z")

az automation schedule create \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$SCHEDULE_NAME" \
  --frequency Day \
  --interval 1 \
  --start-time "$NEXT_0200" \
  --time-zone "$TIMEZONE" \
  -o none \
  || az automation schedule create \
    --resource-group "$RG_OPS" \
    --automation-account-name "$AA_NAME" \
    --name "$SCHEDULE_NAME" \
    --frequency Day \
    --interval 1 \
    --start-time "$NEXT_0200" \
    --timezone "$TIMEZONE" \
    -o none

JOB_SCHEDULE_KEY="${RUNBOOK_NAME}|${SCHEDULE_NAME}"
JOB_SCHEDULE_ID=$(python3 - <<'PY'
import os, uuid
print(uuid.uuid5(uuid.NAMESPACE_URL, os.environ["JOB_SCHEDULE_KEY"]))
PY
)

BODY=$(cat <<JSON
{
  "properties": {
    "schedule": { "name": "$SCHEDULE_NAME" },
    "runbook": { "name": "$RUNBOOK_NAME" }
  }
}
JSON
)

az rest --method put \
  --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Automation/automationAccounts/$AA_NAME/jobSchedules/$JOB_SCHEDULE_ID?api-version=2024-10-23" \
  --body "$BODY" \
  -o none

echo "OK"
echo "Automation Account: $AA_NAME"
echo "Runbook: $RUNBOOK_NAME"
echo "Schedule: $SCHEDULE_NAME ($TIMEZONE @ 02:00)"
