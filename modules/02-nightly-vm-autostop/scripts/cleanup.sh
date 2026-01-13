set -euo pipefail

RG_OPS="rg-ops-guardrails"
AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
SCHEDULE_NAME="sched-stop-vms-0200"

az automation job-schedule list -g "$RG_OPS" -a "$AA_NAME" -o tsv --query "[?runbook.name=='$RUNBOOK_NAME' && schedule.name=='$SCHEDULE_NAME'].jobScheduleId" | while read -r id; do
  [ -z "$id" ] || az automation job-schedule delete -g "$RG_OPS" -a "$AA_NAME" --job-schedule-id "$id" -o none
done

az automation schedule delete -g "$RG_OPS" -a "$AA_NAME" -n "$SCHEDULE_NAME" -y -o none || true
az automation runbook delete -g "$RG_OPS" -a "$AA_NAME" -n "$RUNBOOK_NAME" -y -o none || true
az automation account delete -g "$RG_OPS" -n "$AA_NAME" -y -o none || true

echo "OK"
