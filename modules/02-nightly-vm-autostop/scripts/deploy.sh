set -euo pipefail

LOC="westeurope"
RG_OPS="rg-ops-guardrails"

AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
SCHEDULE_NAME="sched-stop-vms-0200"
TIMEZONE="Europe/Berlin"

RUNBOOK_FILE="../infra/stop-tagged-vms.ps1"

az group create -n "$RG_OPS" -l "$LOC" -o none

az automation account create -g "$RG_OPS" -n "$AA_NAME" -l "$LOC" --assign-identity -o none

SUB_ID=$(az account show --query id -o tsv)
PRINCIPAL_ID=$(az automation account show -g "$RG_OPS" -n "$AA_NAME" --query identity.principalId -o tsv)

az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Virtual Machine Contributor" --scope "/subscriptions/$SUB_ID" -o none

az automation runbook create -g "$RG_OPS" -a "$AA_NAME" -n "$RUNBOOK_NAME" --type PowerShell --location "$LOC" -o none || true

az automation runbook replace-content -g "$RG_OPS" -a "$AA_NAME" -n "$RUNBOOK_NAME" --content @"$RUNBOOK_FILE" -o none
az automation runbook publish -g "$RG_OPS" -a "$AA_NAME" -n "$RUNBOOK_NAME" -o none

NEXT_0200=$(TZ="$TIMEZONE" date -d "tomorrow 02:00" "+%Y-%m-%dT%H:%M:%S%z")

az automation schedule create -g "$RG_OPS" -a "$AA_NAME" -n "$SCHEDULE_NAME" --frequency Day --interval 1 --start-time "$NEXT_0200" --timezone "$TIMEZONE" -o none \
  || az automation schedule create -g "$RG_OPS" -a "$AA_NAME" -n "$SCHEDULE_NAME" --frequency Day --interval 1 --start-time "$NEXT_0200" --time-zone "$TIMEZONE" -o none

az automation job-schedule create -g "$RG_OPS" -a "$AA_NAME" --runbook-name "$RUNBOOK_NAME" --schedule-name "$SCHEDULE_NAME" -o none

echo "OK"
echo "Automation Account: $AA_NAME"
echo "Runbook: $RUNBOOK_NAME"
echo "Schedule: $SCHEDULE_NAME ($TIMEZONE @ 02:00)"
