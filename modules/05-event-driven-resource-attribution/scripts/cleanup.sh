#!/usr/bin/env bash
set -euo pipefail

# Brownfield-safe Module 05 cleanup.
#
# Default behavior is DRY RUN: inspect the exact Module 05 resources and
# assignments that would be removed, but make no Azure changes.
#
# To execute destructive cleanup intentionally:
#   ./cleanup.sh --execute
#
# Shared Foundation resources and external Entra groups are always preserved.

az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

EXECUTE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)
      EXECUTE=true
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./cleanup.sh [--execute]

Without --execute, this script performs a read-only dry run.

With --execute, it removes only Module 05-owned resources and exact Module 05
role assignments. Shared Foundation resources and external Entra groups are
preserved.
USAGE
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_cmd az

RG_FINOPS_LAB="rg-finops-lab"
VNET_NAME="vnet-finops-lab"
SUBNET_NAME="subnet-workload"

FUNCTION_APP_NAME="func-finops-attribution-92096"
STORAGE_ACCOUNT_NAME="stfinopsfunc94976"
APP_SERVICE_PLAN_NAME="ASP-rgfinopslab-bcdf"
APP_INSIGHTS_NAME="func-finops-attribution-92096"

SYSTEM_TOPIC_NAME="${M05_SYSTEM_TOPIC_NAME:-rg-finops-lab-30892968-5599-4372-bc1a-2229e2d9b3aa}"
EVENT_SUBSCRIPTION_NAME="evsub-finops-resource-attribution"

TAGGER_ROLE_NAME="FinOps Resource Attribution Tagger"
ENGINEER_ROLE_NAME="FinOps Lab VM Engineer"
ENGINEER_GROUP_NAME="grp-azure-finops-lab-engineers"
AUDITOR_GROUP_NAME="grp-azure-finops-lab-auditors"

SUB_ID=$(az account show --query id -o tsv)
[[ -n "$SUB_ID" && "$SUB_ID" != "null" ]] || die "No active Azure subscription found."

LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "Subscription: $SUB_ID"
echo "Module 05 scope: $LAB_SCOPE"
echo

echo "Validating shared Foundation resources that must be preserved..."
az group show --name "$RG_FINOPS_LAB" -o none   || die "Shared Foundation Resource Group not found: $RG_FINOPS_LAB"

az network vnet show   --resource-group "$RG_FINOPS_LAB"   --name "$VNET_NAME"   -o none   || die "Shared Foundation VNet not found: $VNET_NAME"

az network vnet subnet show   --resource-group "$RG_FINOPS_LAB"   --vnet-name "$VNET_NAME"   --name "$SUBNET_NAME"   -o none   || die "Shared Foundation subnet not found: $SUBNET_NAME"

echo "- preserve Resource Group: $RG_FINOPS_LAB"
echo "- preserve VNet/subnet: $VNET_NAME/$SUBNET_NAME"

echo
echo "Resolving external Entra groups that must be preserved..."
ENGINEER_GROUP_ID=$(az ad group show --group "$ENGINEER_GROUP_NAME" --query id -o tsv)
AUDITOR_GROUP_ID=$(az ad group show --group "$AUDITOR_GROUP_NAME" --query id -o tsv)

[[ -n "$ENGINEER_GROUP_ID" && "$ENGINEER_GROUP_ID" != "null" ]]   || die "External Entra group not found: $ENGINEER_GROUP_NAME"
[[ -n "$AUDITOR_GROUP_ID" && "$AUDITOR_GROUP_ID" != "null" ]]   || die "External Entra group not found: $AUDITOR_GROUP_NAME"

echo "- preserve Entra group: $ENGINEER_GROUP_NAME ($ENGINEER_GROUP_ID)"
echo "- preserve Entra group: $AUDITOR_GROUP_NAME ($AUDITOR_GROUP_ID)"

resource_exists() {
  local command_name="$1"
  shift

  if "$command_name" "$@" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

delete_exact_role_assignment() {
  local principal_id="$1"
  local role_name="$2"
  local scope="$3"

  local assignment_id
  assignment_id=$(az_no_pathconv role assignment list     --scope "$scope"     --query "[?principalId=='$principal_id' && roleDefinitionName=='$role_name' && scope=='$scope'].id | [0]"     -o tsv)

  if [[ -z "$assignment_id" || "$assignment_id" == "null" ]]; then
    echo "Role assignment not present, skipping: $role_name -> $principal_id"
    return
  fi

  echo "Target role assignment: $role_name -> $principal_id"

  if [[ "$EXECUTE" == "true" ]]; then
    az_no_pathconv role assignment delete       --ids "$assignment_id"
    echo "Deleted role assignment: $role_name -> $principal_id"
  fi
}

delete_custom_role_if_unassigned() {
  local role_name="$1"

  local role_id
  role_id=$(az role definition list     --name "$role_name"     --custom-role-only true     --query "[0].id"     -o tsv)

  if [[ -z "$role_id" || "$role_id" == "null" ]]; then
    echo "Custom role not present, skipping: $role_name"
    return
  fi

  local remaining_count
  remaining_count=$(az role assignment list     --role "$role_name"     --all     --query "length(@)"     -o tsv)

  if [[ "$remaining_count" != "0" ]]; then
    echo "WARNING: Custom role still has $remaining_count assignment(s): $role_name"
    echo "The role definition will NOT be deleted."
    return
  fi

  echo "Target custom role: $role_name"

  if [[ "$EXECUTE" == "true" ]]; then
    az role definition delete       --name "$role_name"
    echo "Deleted custom role: $role_name"
  fi
}

echo
if [[ "$EXECUTE" == "true" ]]; then
  echo "DESTRUCTIVE MODE ENABLED: Module 05-owned resources will be removed."
else
  echo "DRY RUN: no Azure resource will be changed."
fi

echo
echo "Inspecting Module 05 Function Managed Identity..."
FUNCTION_PRINCIPAL_ID=""

if az functionapp show   --resource-group "$RG_FINOPS_LAB"   --name "$FUNCTION_APP_NAME"   -o none >/dev/null 2>&1; then

  FUNCTION_PRINCIPAL_ID=$(az functionapp identity show     --resource-group "$RG_FINOPS_LAB"     --name "$FUNCTION_APP_NAME"     --query principalId     -o tsv)

  echo "Function App present: $FUNCTION_APP_NAME"
  echo "Function Managed Identity: $FUNCTION_PRINCIPAL_ID"
else
  echo "Function App not present: $FUNCTION_APP_NAME"
fi

echo
echo "Processing exact Module 05 role assignments..."

delete_exact_role_assignment   "$ENGINEER_GROUP_ID"   "$ENGINEER_ROLE_NAME"   "$LAB_SCOPE"

delete_exact_role_assignment   "$AUDITOR_GROUP_ID"   "Reader"   "$LAB_SCOPE"

if [[ -n "$FUNCTION_PRINCIPAL_ID" && "$FUNCTION_PRINCIPAL_ID" != "null" ]]; then
  delete_exact_role_assignment     "$FUNCTION_PRINCIPAL_ID"     "$TAGGER_ROLE_NAME"     "$LAB_SCOPE"
else
  echo "Function principal unavailable; no Function tagger assignment can be safely targeted."
fi

echo
echo "Processing Event Grid event subscription..."

if az_no_pathconv eventgrid system-topic event-subscription show   --resource-group "$RG_FINOPS_LAB"   --system-topic-name "$SYSTEM_TOPIC_NAME"   --name "$EVENT_SUBSCRIPTION_NAME"   -o none >/dev/null 2>&1; then

  echo "Target event subscription: $EVENT_SUBSCRIPTION_NAME"

  if [[ "$EXECUTE" == "true" ]]; then
    az_no_pathconv eventgrid system-topic event-subscription delete       --resource-group "$RG_FINOPS_LAB"       --system-topic-name "$SYSTEM_TOPIC_NAME"       --name "$EVENT_SUBSCRIPTION_NAME"       --yes
    echo "Deleted event subscription: $EVENT_SUBSCRIPTION_NAME"
  fi
else
  echo "Event subscription not present, skipping: $EVENT_SUBSCRIPTION_NAME"
fi

echo
echo "Processing Event Grid system topic..."

if az_no_pathconv eventgrid system-topic show   --resource-group "$RG_FINOPS_LAB"   --name "$SYSTEM_TOPIC_NAME"   -o none >/dev/null 2>&1; then

  echo "Target system topic: $SYSTEM_TOPIC_NAME"

  if [[ "$EXECUTE" == "true" ]]; then
    az_no_pathconv eventgrid system-topic delete       --resource-group "$RG_FINOPS_LAB"       --name "$SYSTEM_TOPIC_NAME"       --yes
    echo "Deleted system topic: $SYSTEM_TOPIC_NAME"
  fi
else
  echo "System topic not present, skipping: $SYSTEM_TOPIC_NAME"
fi

echo
echo "Processing Function App..."

if az functionapp show   --resource-group "$RG_FINOPS_LAB"   --name "$FUNCTION_APP_NAME"   -o none >/dev/null 2>&1; then

  echo "Target Function App: $FUNCTION_APP_NAME"

  if [[ "$EXECUTE" == "true" ]]; then
    az functionapp delete       --resource-group "$RG_FINOPS_LAB"       --name "$FUNCTION_APP_NAME"
    echo "Deleted Function App: $FUNCTION_APP_NAME"
  fi
else
  echo "Function App not present, skipping: $FUNCTION_APP_NAME"
fi

echo
echo "Processing Application Insights..."

if az monitor app-insights component show   --resource-group "$RG_FINOPS_LAB"   --app "$APP_INSIGHTS_NAME"   -o none >/dev/null 2>&1; then

  echo "Target Application Insights component: $APP_INSIGHTS_NAME"

  if [[ "$EXECUTE" == "true" ]]; then
    az monitor app-insights component delete       --resource-group "$RG_FINOPS_LAB"       --app "$APP_INSIGHTS_NAME"
    echo "Deleted Application Insights component: $APP_INSIGHTS_NAME"
  fi
else
  echo "Application Insights component not present, skipping: $APP_INSIGHTS_NAME"
fi

echo
echo "Processing Flex Consumption plan..."

if az appservice plan show   --resource-group "$RG_FINOPS_LAB"   --name "$APP_SERVICE_PLAN_NAME"   -o none >/dev/null 2>&1; then

  echo "Target Flex Consumption plan: $APP_SERVICE_PLAN_NAME"

  if [[ "$EXECUTE" == "true" ]]; then
    az appservice plan delete       --resource-group "$RG_FINOPS_LAB"       --name "$APP_SERVICE_PLAN_NAME"       --yes
    echo "Deleted Flex Consumption plan: $APP_SERVICE_PLAN_NAME"
  fi
else
  echo "Flex Consumption plan not present, skipping: $APP_SERVICE_PLAN_NAME"
fi

echo
echo "Processing Function Storage Account..."

if az storage account show   --resource-group "$RG_FINOPS_LAB"   --name "$STORAGE_ACCOUNT_NAME"   -o none >/dev/null 2>&1; then

  echo "Target Storage Account: $STORAGE_ACCOUNT_NAME"

  if [[ "$EXECUTE" == "true" ]]; then
    az storage account delete       --resource-group "$RG_FINOPS_LAB"       --name "$STORAGE_ACCOUNT_NAME"       --yes
    echo "Deleted Storage Account: $STORAGE_ACCOUNT_NAME"
  fi
else
  echo "Storage Account not present, skipping: $STORAGE_ACCOUNT_NAME"
fi

echo
echo "Processing Module 05 custom role definitions..."
delete_custom_role_if_unassigned "$TAGGER_ROLE_NAME"
delete_custom_role_if_unassigned "$ENGINEER_ROLE_NAME"

echo
echo "Cleanup processing complete."

if [[ "$EXECUTE" == "true" ]]; then
  echo "Module 05 destructive cleanup executed."
else
  echo "Dry run complete. No Azure changes were made."
fi

echo
echo "Preserved by design:"
echo "- Resource Group: $RG_FINOPS_LAB"
echo "- Foundation governance tag values"
echo "- VNet/subnet: $VNET_NAME/$SUBNET_NAME"
echo "- Entra groups: $ENGINEER_GROUP_NAME, $AUDITOR_GROUP_NAME"
echo "- Module 03 / Module 04 policy resources"
echo "- unrelated resources and assignments in the shared lab scope"
echo
echo "NOTE:"
echo "The service-generated Application Insights Smart Detection action group is"
echo "not targeted directly by this script."
