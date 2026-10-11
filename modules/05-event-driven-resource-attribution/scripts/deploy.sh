#!/usr/bin/env bash
set -euo pipefail

# Brownfield-safe Module 05 deployment/reconciliation.
#
# Default behavior:
# - validates shared Foundation resources and external Entra groups
# - creates missing Module 05 role definitions / exact role assignments
# - validates existing Function infrastructure without replacing it
# - creates or validates Event Grid wiring
# - does NOT create/delete shared Foundation resources
# - does NOT create/delete Entra groups
# - does NOT write Foundation governance tag values
#
# Optional:
#   ./deploy.sh --deploy-code
# packages the local Python Function project and deploys it to the existing
# Flex Consumption Function App using Azure Functions package deployment.

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

DEPLOY_CODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-code)
      DEPLOY_CODE=true
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./deploy.sh [--deploy-code]

Without --deploy-code, the script performs Brownfield-safe validation and
reconciliation of Module 05 control-plane resources.

With --deploy-code, it also packages and deploys the Python Function code to
the existing Flex Consumption Function App.
USAGE
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_cmd az
require_cmd python3

RG_FINOPS_LAB="rg-finops-lab"
LOCATION="westeurope"
VNET_NAME="vnet-finops-lab"
SUBNET_NAME="subnet-workload"

FUNCTION_APP_NAME="func-finops-attribution-92096"
FUNCTION_NAME="ResourceAttribution"
STORAGE_ACCOUNT_NAME="stfinopsfunc94976"
APP_SERVICE_PLAN_NAME="ASP-rgfinopslab-bcdf"
APP_INSIGHTS_NAME="func-finops-attribution-92096"

SYSTEM_TOPIC_NAME="${M05_SYSTEM_TOPIC_NAME:-rg-finops-lab-30892968-5599-4372-bc1a-2229e2d9b3aa}"
EVENT_SUBSCRIPTION_NAME="evsub-finops-resource-attribution"
EVENT_TYPE="Microsoft.Resources.ResourceWriteSuccess"

TAGGER_ROLE_NAME="FinOps Resource Attribution Tagger"
ENGINEER_ROLE_NAME="FinOps Lab VM Engineer"
ENGINEER_GROUP_NAME="grp-azure-finops-lab-engineers"
AUDITOR_GROUP_NAME="grp-azure-finops-lab-auditors"

REQUIRED_FOUNDATION_TAGS=(
  "Environment"
  "Project"
  "CostCenter"
  "Owner"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$MODULE_DIR/infra"
FUNCTION_DIR="$MODULE_DIR/function"

TAGGER_ROLE_FILE="$INFRA_DIR/finops-resource-attribution-tagger.role.json"
ENGINEER_ROLE_FILE="$INFRA_DIR/finops-lab-vm-engineer.role.json"

SUB_ID=$(az account show --query id -o tsv)
[[ -n "$SUB_ID" && "$SUB_ID" != "null" ]] || die "No active Azure subscription found."

LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"
FUNCTION_ID="$LAB_SCOPE/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME"
FUNCTION_ENDPOINT_ID="$FUNCTION_ID/functions/$FUNCTION_NAME"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

validate_json_file() {
  local json_file="$1"

  python3 - "$json_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8-sig") as f:
    json.load(f)
PY
}

echo "Running local repository preflight..."

for role_file in "$TAGGER_ROLE_FILE" "$ENGINEER_ROLE_FILE"; do
  [[ -f "$role_file" ]] || die "Role definition file not found: $role_file"
  validate_json_file "$role_file"     || die "Invalid JSON in role definition file: $role_file"
done

for function_file in function_app.py host.json requirements.txt; do
  [[ -f "$FUNCTION_DIR/$function_file" ]]     || die "Required Function project file missing: $FUNCTION_DIR/$function_file"
done

validate_json_file "$FUNCTION_DIR/host.json"   || die "Invalid JSON in Function host.json"

python3 - "$FUNCTION_DIR/function_app.py" <<'PY'
import ast
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
print("Function Python syntax validated.")
PY

echo "Local repository preflight passed."
echo
echo "Subscription: $SUB_ID"
echo "Module 05 scope: $LAB_SCOPE"
echo

echo "Validating shared Foundation Resource Group..."
az group show --name "$RG_FINOPS_LAB" -o none \
  || die "Shared Foundation Resource Group not found: $RG_FINOPS_LAB"

echo "Found shared Resource Group: $RG_FINOPS_LAB"
echo
echo "Validating required Foundation governance tags..."

for TAG_NAME in "${REQUIRED_FOUNDATION_TAGS[@]}"; do
  TAG_VALUE=$(az group show \
    --name "$RG_FINOPS_LAB" \
    --query "tags.${TAG_NAME}" \
    -o tsv)

  if [[ -z "$TAG_VALUE" || "$TAG_VALUE" == "null" ]]; then
    die "Required Foundation tag is missing or empty: $TAG_NAME"
  fi

  echo "- $TAG_NAME=$TAG_VALUE"
done

echo
echo "Validating shared Foundation network..."
az network vnet show \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$VNET_NAME" \
  -o none \
  || die "Shared Foundation VNet not found: $VNET_NAME"

az network vnet subnet show \
  --resource-group "$RG_FINOPS_LAB" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_NAME" \
  -o none \
  || die "Shared Foundation subnet not found: $SUBNET_NAME"

echo "Found shared network: $VNET_NAME/$SUBNET_NAME"

echo
echo "Resolving external Entra groups..."
ENGINEER_GROUP_ID=$(az ad group show --group "$ENGINEER_GROUP_NAME" --query id -o tsv)
AUDITOR_GROUP_ID=$(az ad group show --group "$AUDITOR_GROUP_NAME" --query id -o tsv)

[[ -n "$ENGINEER_GROUP_ID" && "$ENGINEER_GROUP_ID" != "null" ]] \
  || die "External Entra group not found: $ENGINEER_GROUP_NAME"
[[ -n "$AUDITOR_GROUP_ID" && "$AUDITOR_GROUP_ID" != "null" ]] \
  || die "External Entra group not found: $AUDITOR_GROUP_NAME"

echo "- $ENGINEER_GROUP_NAME: $ENGINEER_GROUP_ID"
echo "- $AUDITOR_GROUP_NAME: $AUDITOR_GROUP_ID"

materialize_role_definition() {
  local source_file="$1"
  local destination_file="$2"

  [[ -f "$source_file" ]] || die "Role definition file not found: $source_file"

  python3 - "$source_file" "$destination_file" "$SUB_ID" <<'PY'
import json
import sys

source_file, destination_file, subscription_id = sys.argv[1:4]

with open(source_file, "r", encoding="utf-8-sig") as f:
    role = json.load(f)

role["AssignableScopes"] = [f"/subscriptions/{subscription_id}"]

with open(destination_file, "w", encoding="utf-8") as f:
    json.dump(role, f, indent=2)
    f.write("\n")
PY
}

validate_role_definition() {
  local role_name="$1"
  local expected_file="$2"
  local live_file="$TMP_DIR/$(echo "$role_name" | tr ' /' '__').live.json"

  az role definition list \
    --name "$role_name" \
    --custom-role-only true \
    -o json > "$live_file"

  python3 - "$expected_file" "$live_file" "$role_name" <<'PY'
import json
import sys

expected_file, live_file, role_name = sys.argv[1:4]

with open(expected_file, "r", encoding="utf-8-sig") as f:
    expected = json.load(f)

with open(live_file, "r", encoding="utf-8-sig") as f:
    live_items = json.load(f)

if len(live_items) != 1:
    print(f"ERROR: Expected exactly one custom role definition for {role_name}, found {len(live_items)}")
    sys.exit(1)

live = live_items[0]

checks = {
    "roleName": (expected.get("Name"), live.get("roleName")),
    "description": (expected.get("Description"), live.get("description")),
    "actions": (sorted(expected.get("Actions", [])), sorted(live.get("permissions", [{}])[0].get("actions", []))),
    "notActions": (sorted(expected.get("NotActions", [])), sorted(live.get("permissions", [{}])[0].get("notActions", []))),
    "dataActions": (sorted(expected.get("DataActions", [])), sorted(live.get("permissions", [{}])[0].get("dataActions", []))),
    "notDataActions": (sorted(expected.get("NotDataActions", [])), sorted(live.get("permissions", [{}])[0].get("notDataActions", []))),
    "assignableScopes": (sorted(expected.get("AssignableScopes", [])), sorted(live.get("assignableScopes", []))),
}

drift = [(field, wanted, actual) for field, (wanted, actual) in checks.items() if wanted != actual]

if drift:
    print(f"ERROR: Custom role drift detected: {role_name}")
    for field, wanted, actual in drift:
        print(f"- {field}")
        print("  expected:", json.dumps(wanted, ensure_ascii=False, sort_keys=True))
        print("  actual:  ", json.dumps(actual, ensure_ascii=False, sort_keys=True))
    sys.exit(1)

print(f"Custom role validated: {role_name}")
PY
}

create_or_validate_role_definition() {
  local role_name="$1"
  local source_file="$2"
  local rendered_file="$TMP_DIR/$(echo "$role_name" | tr ' /' '__').expected.json"

  materialize_role_definition "$source_file" "$rendered_file"

  local role_id
  role_id=$(az role definition list \
    --name "$role_name" \
    --custom-role-only true \
    --query "[0].id" \
    -o tsv)

  if [[ -z "$role_id" || "$role_id" == "null" ]]; then
    echo "Custom role missing. Creating: $role_name"
    az role definition create --role-definition "$rendered_file" -o none
  else
    echo "Custom role already exists: $role_name"
  fi

  validate_role_definition "$role_name" "$rendered_file"
}

create_or_validate_role_assignment() {
  local principal_id="$1"
  local principal_type="$2"
  local role_name="$3"
  local scope="$4"

  local assignment_id
  assignment_id=$(az_no_pathconv role assignment list \
    --scope "$scope" \
    --query "[?principalId=='$principal_id' && roleDefinitionName=='$role_name' && scope=='$scope'].id | [0]" \
    -o tsv)

  if [[ -z "$assignment_id" || "$assignment_id" == "null" ]]; then
    echo "Role assignment missing. Creating: $role_name -> $principal_id"
    az_no_pathconv role assignment create \
      --assignee-object-id "$principal_id" \
      --assignee-principal-type "$principal_type" \
      --role "$role_name" \
      --scope "$scope" \
      -o none
  else
    echo "Role assignment already exists: $role_name -> $principal_id"
  fi

  assignment_id=$(az_no_pathconv role assignment list \
    --scope "$scope" \
    --query "[?principalId=='$principal_id' && roleDefinitionName=='$role_name' && scope=='$scope'].id | [0]" \
    -o tsv)

  [[ -n "$assignment_id" && "$assignment_id" != "null" ]] \
    || die "Role assignment could not be confirmed: $role_name -> $principal_id"
}

echo
echo "Reconciling Module 05 custom roles..."
create_or_validate_role_definition "$TAGGER_ROLE_NAME" "$TAGGER_ROLE_FILE"
create_or_validate_role_definition "$ENGINEER_ROLE_NAME" "$ENGINEER_ROLE_FILE"

echo
echo "Reconciling group-based workload RBAC..."
create_or_validate_role_assignment "$ENGINEER_GROUP_ID" "Group" "$ENGINEER_ROLE_NAME" "$LAB_SCOPE"
create_or_validate_role_assignment "$AUDITOR_GROUP_ID" "Group" "Reader" "$LAB_SCOPE"

echo
echo "Validating existing Function Storage Account..."
STORAGE_JSON="$TMP_DIR/storage.json"
az storage account show \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$STORAGE_ACCOUNT_NAME" \
  -o json > "$STORAGE_JSON" \
  || die "Module 05 Storage Account not found: $STORAGE_ACCOUNT_NAME"

python3 - "$STORAGE_JSON" "$STORAGE_ACCOUNT_NAME" "$LOCATION" <<'PY'
import json
import sys

path, expected_name, expected_location = sys.argv[1:4]
with open(path, "r", encoding="utf-8-sig") as f:
    live = json.load(f)

checks = {
    "name": (expected_name, live.get("name")),
    "location": (expected_location.lower(), str(live.get("location", "")).lower()),
    "kind": ("StorageV2", live.get("kind")),
    "sku": ("Standard_LRS", live.get("sku", {}).get("name")),
    "provisioningState": ("Succeeded", live.get("provisioningState")),
}

drift = [(k, e, a) for k, (e, a) in checks.items() if e != a]
if drift:
    print("ERROR: Function Storage Account drift detected.")
    for k, e, a in drift:
        print(f"- {k}: expected={e!r} actual={a!r}")
    sys.exit(1)

print("Function Storage Account validated.")
PY

echo
echo "Validating existing Flex Consumption plan..."
PLAN_JSON="$TMP_DIR/plan.json"
az appservice plan show \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$APP_SERVICE_PLAN_NAME" \
  -o json > "$PLAN_JSON" \
  || die "Module 05 Flex Consumption plan not found: $APP_SERVICE_PLAN_NAME"

python3 - "$PLAN_JSON" "$APP_SERVICE_PLAN_NAME" "$LOCATION" <<'PY'
import json
import sys

path, expected_name, expected_location = sys.argv[1:4]
with open(path, "r", encoding="utf-8-sig") as f:
    live = json.load(f)

checks = {
    "name": (expected_name, live.get("name")),
    "location": (expected_location.lower(), str(live.get("location", "")).replace(" ", "").lower()),
    "sku.name": ("FC1", live.get("sku", {}).get("name")),
    "sku.tier": ("FlexConsumption", live.get("sku", {}).get("tier")),
}

drift = [(k, e, a) for k, (e, a) in checks.items() if e != a]
if drift:
    print("ERROR: Flex Consumption plan drift detected.")
    for k, e, a in drift:
        print(f"- {k}: expected={e!r} actual={a!r}")
    sys.exit(1)

print("Flex Consumption plan validated.")
PY

echo
echo "Validating Application Insights..."
APP_INSIGHTS_JSON="$TMP_DIR/appinsights.json"
az monitor app-insights component show \
  --resource-group "$RG_FINOPS_LAB" \
  --app "$APP_INSIGHTS_NAME" \
  -o json > "$APP_INSIGHTS_JSON" \
  || die "Application Insights component not found: $APP_INSIGHTS_NAME"

python3 - "$APP_INSIGHTS_JSON" "$APP_INSIGHTS_NAME" "$LOCATION" <<'PY'
import json
import sys

path, expected_name, expected_location = sys.argv[1:4]
with open(path, "r", encoding="utf-8-sig") as f:
    live = json.load(f)

checks = {
    "name": (expected_name, live.get("name")),
    "location": (expected_location.lower(), str(live.get("location", "")).replace(" ", "").lower()),
    "applicationType": ("web", live.get("applicationType")),
    "provisioningState": ("Succeeded", live.get("provisioningState")),
}

drift = [(k, e, a) for k, (e, a) in checks.items() if e != a]
if drift:
    print("ERROR: Application Insights drift detected.")
    for k, e, a in drift:
        print(f"- {k}: expected={e!r} actual={a!r}")
    sys.exit(1)

print("Application Insights validated.")
PY

echo
echo "Validating Function App and runtime..."
FUNCTION_JSON="$TMP_DIR/function.json"
az functionapp show \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$FUNCTION_APP_NAME" \
  -o json > "$FUNCTION_JSON" \
  || die "Function App not found: $FUNCTION_APP_NAME"

RUNTIME_JSON="$TMP_DIR/runtime.json"
az_no_pathconv resource show \
  --ids "$FUNCTION_ID" \
  --query "properties.functionAppConfig.runtime" \
  -o json > "$RUNTIME_JSON"

python3 - "$FUNCTION_JSON" "$RUNTIME_JSON" "$FUNCTION_APP_NAME" "$LOCATION" <<'PY'
import json
import sys

function_path, runtime_path, expected_name, expected_location = sys.argv[1:5]
with open(function_path, "r", encoding="utf-8-sig") as f:
    function = json.load(f)
with open(runtime_path, "r", encoding="utf-8-sig") as f:
    runtime = json.load(f)

checks = {
    "name": (expected_name, function.get("name")),
    "location": (expected_location.lower(), str(function.get("location", "")).replace(" ", "").lower()),
    "identity.type": ("SystemAssigned", function.get("identity", {}).get("type")),
    "runtime.name": ("python", runtime.get("name")),
    "runtime.version": ("3.14", str(runtime.get("version"))),
}

drift = [(k, e, a) for k, (e, a) in checks.items() if e != a]
if drift:
    print("ERROR: Function App drift detected.")
    for k, e, a in drift:
        print(f"- {k}: expected={e!r} actual={a!r}")
    sys.exit(1)

print("Function App runtime and identity validated.")
PY

FUNCTION_PRINCIPAL_ID=$(az functionapp identity show \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$FUNCTION_APP_NAME" \
  --query principalId \
  -o tsv)

[[ -n "$FUNCTION_PRINCIPAL_ID" && "$FUNCTION_PRINCIPAL_ID" != "null" ]] \
  || die "Function Managed Identity principalId is missing."

echo "Function Managed Identity: $FUNCTION_PRINCIPAL_ID"

echo
echo "Reconciling Function tagger RBAC..."
create_or_validate_role_assignment "$FUNCTION_PRINCIPAL_ID" "ServicePrincipal" "$TAGGER_ROLE_NAME" "$LAB_SCOPE"

echo
echo "Validating Function storage settings without printing secrets..."
APPSETTINGS_JSON="$TMP_DIR/appsettings.json"
STORAGE_KEYS_JSON="$TMP_DIR/storage-keys.json"

az functionapp config appsettings list \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$FUNCTION_APP_NAME" \
  -o json > "$APPSETTINGS_JSON"

az storage account keys list \
  --resource-group "$RG_FINOPS_LAB" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  -o json > "$STORAGE_KEYS_JSON"

python3 - "$APPSETTINGS_JSON" "$STORAGE_KEYS_JSON" "$STORAGE_ACCOUNT_NAME" <<'PY'
import json
import re
import sys

settings_path, keys_path, expected_account = sys.argv[1:4]

with open(settings_path, "r", encoding="utf-8-sig") as f:
    settings_list = json.load(f)
with open(keys_path, "r", encoding="utf-8-sig") as f:
    keys = json.load(f)

settings = {item.get("name"): item.get("value") for item in settings_list}
active_keys = {item.get("value") for item in keys if item.get("value")}

errors = []
for setting_name in ("AzureWebJobsStorage", "DEPLOYMENT_STORAGE_CONNECTION_STRING"):
    value = settings.get(setting_name)
    if not value:
        errors.append(f"{setting_name} is missing or empty")
        continue

    account_match = re.search(r"(?:^|;)AccountName=([^;]+)", value, re.IGNORECASE)
    key_match = re.search(r"(?:^|;)AccountKey=([^;]+)", value, re.IGNORECASE)

    account = account_match.group(1) if account_match else None
    key = key_match.group(1) if key_match else None

    if account != expected_account:
        errors.append(f"{setting_name} points to unexpected Storage Account")
    if not key or key not in active_keys:
        errors.append(f"{setting_name} does not use a currently active Storage Account key")

if not settings.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    errors.append("APPLICATIONINSIGHTS_CONNECTION_STRING is missing or empty")

if errors:
    print("ERROR: Function app setting validation failed.")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print("Function storage and Application Insights settings validated.")
PY

if [[ "$DEPLOY_CODE" == "true" ]]; then
  echo
  echo "Packaging and deploying Function code..."

  for required_file in function_app.py host.json requirements.txt; do
    [[ -f "$FUNCTION_DIR/$required_file" ]] \
      || die "Required Function project file missing: $FUNCTION_DIR/$required_file"
  done

  FUNCTION_ZIP="$TMP_DIR/function.zip"

  python3 - "$FUNCTION_DIR" "$FUNCTION_ZIP" <<'PY'
import os
import sys
import zipfile

source_dir, zip_path = sys.argv[1:3]
include = ["function_app.py", "host.json", "requirements.txt"]

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name in include:
        zf.write(os.path.join(source_dir, name), arcname=name)
PY

  ZIP_ARG="$FUNCTION_ZIP"
  if command -v cygpath >/dev/null 2>&1; then
    ZIP_ARG=$(cygpath -w "$FUNCTION_ZIP")
  fi

  az functionapp deployment source config-zip \
    --resource-group "$RG_FINOPS_LAB" \
    --name "$FUNCTION_APP_NAME" \
    --src "$ZIP_ARG" \
    --build-remote true \
    -o none

  echo "Function package deployment completed."
fi

echo
echo "Validating deployed Function trigger..."
FUNCTION_TRIGGER=$(az functionapp function list \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$FUNCTION_APP_NAME" \
  --query "[?name=='$FUNCTION_APP_NAME/$FUNCTION_NAME'].name | [0]" \
  -o tsv)

[[ -n "$FUNCTION_TRIGGER" && "$FUNCTION_TRIGGER" != "null" ]] \
  || die "Function trigger not found: $FUNCTION_NAME"

echo "Function trigger found: $FUNCTION_TRIGGER"

echo
echo "Reconciling Event Grid system topic..."
if ! az_no_pathconv eventgrid system-topic show \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$SYSTEM_TOPIC_NAME" \
  -o none 2>/dev/null; then

  echo "System topic missing. Creating: $SYSTEM_TOPIC_NAME"
  az_no_pathconv eventgrid system-topic create \
    --resource-group "$RG_FINOPS_LAB" \
    --name "$SYSTEM_TOPIC_NAME" \
    --location global \
    --source "$LAB_SCOPE" \
    --topic-type Microsoft.Resources.ResourceGroups \
    -o none
else
  echo "System topic already exists: $SYSTEM_TOPIC_NAME"
fi

TOPIC_JSON="$TMP_DIR/system-topic.json"
az_no_pathconv eventgrid system-topic show \
  --resource-group "$RG_FINOPS_LAB" \
  --name "$SYSTEM_TOPIC_NAME" \
  -o json > "$TOPIC_JSON"

python3 - "$TOPIC_JSON" "$SYSTEM_TOPIC_NAME" "$SUB_ID" "$RG_FINOPS_LAB" <<'PY'
import json
import sys

path, expected_name, subscription_id, rg_name = sys.argv[1:5]
expected_source = f"/subscriptions/{subscription_id}/resourceGroups/{rg_name}"

with open(path, "r", encoding="utf-8-sig") as f:
    live = json.load(f)

checks = {
    "name": (expected_name, live.get("name")),
    "source": (expected_source.lower(), str(live.get("source", "")).lower()),
    "topicType": ("microsoft.resources.resourcegroups", str(live.get("topicType", "")).lower()),
    "provisioningState": ("Succeeded", live.get("provisioningState")),
}

drift = [(k, e, a) for k, (e, a) in checks.items() if e != a]
if drift:
    print("ERROR: Event Grid system topic drift detected.")
    for k, e, a in drift:
        print(f"- {k}: expected={e!r} actual={a!r}")
    sys.exit(1)

print("Event Grid system topic validated.")
PY

echo
echo "Reconciling Event Grid event subscription..."
if ! az_no_pathconv eventgrid system-topic event-subscription show \
  --resource-group "$RG_FINOPS_LAB" \
  --system-topic-name "$SYSTEM_TOPIC_NAME" \
  --name "$EVENT_SUBSCRIPTION_NAME" \
  -o none 2>/dev/null; then

  echo "Event subscription missing. Creating: $EVENT_SUBSCRIPTION_NAME"
  az_no_pathconv eventgrid system-topic event-subscription create \
    --resource-group "$RG_FINOPS_LAB" \
    --system-topic-name "$SYSTEM_TOPIC_NAME" \
    --name "$EVENT_SUBSCRIPTION_NAME" \
    --endpoint "$FUNCTION_ENDPOINT_ID" \
    --endpoint-type azurefunction \
    --included-event-types "$EVENT_TYPE" \
    --event-delivery-schema eventgridschema \
    -o none
else
  echo "Event subscription already exists: $EVENT_SUBSCRIPTION_NAME"
fi

EVENT_SUB_JSON="$TMP_DIR/event-subscription.json"
az_no_pathconv eventgrid system-topic event-subscription show \
  --resource-group "$RG_FINOPS_LAB" \
  --system-topic-name "$SYSTEM_TOPIC_NAME" \
  --name "$EVENT_SUBSCRIPTION_NAME" \
  -o json > "$EVENT_SUB_JSON"

python3 - "$EVENT_SUB_JSON" "$EVENT_SUBSCRIPTION_NAME" "$SUB_ID" "$RG_FINOPS_LAB" "$FUNCTION_APP_NAME" "$FUNCTION_NAME" "$EVENT_TYPE" <<'PY'
import json
import sys

(path, expected_name, subscription_id, rg_name,
 function_app_name, function_name, event_type) = sys.argv[1:8]

expected_endpoint = (
    f"/subscriptions/{subscription_id}/resourceGroups/{rg_name}"
    f"/providers/Microsoft.Web/sites/{function_app_name}/functions/{function_name}"
)

with open(path, "r", encoding="utf-8-sig") as f:
    live = json.load(f)

destination = live.get("destination", {}) or {}
filter_obj = live.get("filter", {}) or {}

checks = {
    "name": (expected_name, live.get("name")),
    "provisioningState": ("Succeeded", live.get("provisioningState")),
    "destination.endpointType": ("AzureFunction", destination.get("endpointType")),
    "destination.resourceId": (expected_endpoint.lower(), str(destination.get("resourceId", "")).lower()),
    "includedEventTypes": ([event_type], filter_obj.get("includedEventTypes", [])),
    "eventDeliverySchema": ("EventGridSchema", live.get("eventDeliverySchema")),
}

drift = [(k, e, a) for k, (e, a) in checks.items() if e != a]
if drift:
    print("ERROR: Event Grid event subscription drift detected.")
    for k, e, a in drift:
        print(f"- {k}: expected={e!r} actual={a!r}")
    sys.exit(1)

print("Event Grid event subscription validated.")
PY

echo
echo "Module 05 Brownfield deployment/reconciliation successful."
echo
echo "Shared / external resources preserved:"
echo "- Resource Group: $RG_FINOPS_LAB"
echo "- Foundation governance tag values"
echo "- VNet/subnet: $VNET_NAME/$SUBNET_NAME"
echo "- Entra groups: $ENGINEER_GROUP_NAME, $AUDITOR_GROUP_NAME"
echo
echo "Module 05 validated/reconciled:"
echo "- Custom roles and exact role assignments"
echo "- Existing Flex Consumption Function infrastructure"
echo "- Function Managed Identity tagger RBAC"
echo "- Event Grid system topic and event subscription"

if [[ "$DEPLOY_CODE" == "true" ]]; then
  echo "- Function code package deployed from repository source"
else
  echo "- Function code deployment skipped (use --deploy-code to publish repository code)"
fi

echo
echo "NOTE:"
echo "This Brownfield-safe script intentionally fails if the core Function App,"
echo "Storage Account, Flex Consumption plan, or Application Insights component"
echo "is missing. Those existing resources are preserved for deliberate Terraform"
echo "import rather than recreated implicitly during Brownfield hardening."
