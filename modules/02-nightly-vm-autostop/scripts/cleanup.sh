set -euo pipefail

RG_OPS="rg-ops-guardrails"
AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
SCHEDULE_NAME="sched-stop-vms-0200"

SUB_ID=$(az account show --query id -o tsv)

JOB_SCHEDULE_KEY="${RUNBOOK_NAME}|${SCHEDULE_NAME}"
JOB_SCHEDULE_ID=$(python3 - <<'PY'
import os, uuid
print(uuid.uuid5(uuid.NAMESPACE_URL, os.environ["JOB_SCHEDULE_KEY"]))
PY
)

az rest --method delete \
  --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Automation/automationAccounts/$AA_NAME/jobSchedules/$JOB_SCHEDULE_ID?api-version=2024-10-23" \
  -o none || true

az automation schedule delete \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$SCHEDULE_NAME" \
  -y -o none || true

az automation runbook delete \
  --resource-group "$RG_OPS" \
  --automation-account-name "$AA_NAME" \
  --name "$RUNBOOK_NAME" \
  -y -o none || true

az automation account delete \
  --resource-group "$RG_OPS" \
  --name "$AA_NAME" \
  -y -o none || true

echo "OK"
