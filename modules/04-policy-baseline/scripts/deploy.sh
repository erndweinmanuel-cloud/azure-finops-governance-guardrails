#!/usr/bin/env bash
set -euo pipefail

az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

RG_FINOPS_LAB="rg-finops-lab"
POLICY_DEFINITION_API_VERSION="2021-06-01"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$MODULE_DIR/infra"

REQUIRED_FOUNDATION_TAGS=(
  "Environment"
  "Project"
  "CostCenter"
  "Owner"
)

SUB_ID=$(az account show --query id -o tsv)

[[ -n "$SUB_ID" ]] || {
  echo "ERROR: No active Azure subscription found."
  exit 1
}

LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Subscription: $SUB_ID"
echo
echo "Validating shared Foundation Resource Group..."

if ! az group show --name "$RG_FINOPS_LAB" -o none; then
  echo "ERROR: Shared Foundation Resource Group not found: $RG_FINOPS_LAB"
  echo "Module 04 does not create Foundation Resource Groups."
  exit 1
fi

echo "Found shared Resource Group: $RG_FINOPS_LAB"
echo
echo "Validating required Foundation governance tags..."

for TAG_NAME in "${REQUIRED_FOUNDATION_TAGS[@]}"; do
  TAG_VALUE=$(az group show \
    --name "$RG_FINOPS_LAB" \
    --query "tags.${TAG_NAME}" \
    -o tsv)

  if [[ -z "$TAG_VALUE" || "$TAG_VALUE" == "null" ]]; then
    echo "ERROR: Required Foundation tag is missing or empty: $TAG_NAME"
    echo "Module 04 consumes the shared governance model but does not own these tags."
    exit 1
  fi

  echo "- $TAG_NAME=$TAG_VALUE"
done

validate_policy_definition() {
  local definition_name="$1"
  local policy_file="$2"
  local live_file="$TMP_DIR/${definition_name}.live.json"

  az policy definition show \
    --name "$definition_name" \
    -o json > "$live_file"

  python3 - "$policy_file" "$live_file" "$definition_name" <<'PY'
import json
import sys

policy_file, live_file, name = sys.argv[1:4]

with open(policy_file, "r", encoding="utf-8-sig") as f:
    expected = json.load(f)["properties"]

with open(live_file, "r", encoding="utf-8-sig") as f:
    live = json.load(f)

checks = {
    "displayName": (expected.get("displayName"), live.get("displayName")),
    "description": (expected.get("description"), live.get("description")),
    "policyType": (expected.get("policyType"), live.get("policyType")),
    "mode": (expected.get("mode"), live.get("mode")),
    "parameters": (expected.get("parameters", {}), live.get("parameters", {})),
    "policyRule": (expected.get("policyRule", {}), live.get("policyRule", {})),
    "metadata.category": (
        expected.get("metadata", {}).get("category"),
        live.get("metadata", {}).get("category"),
    ),
    "metadata.version": (
        expected.get("metadata", {}).get("version"),
        live.get("metadata", {}).get("version"),
    ),
}

drift = [(field, wanted, actual)
         for field, (wanted, actual) in checks.items()
         if wanted != actual]

if drift:
    print(f"ERROR: Policy definition drift detected: {name}")
    for field, wanted, actual in drift:
        print(f"- {field}")
        print("  expected:", json.dumps(wanted, ensure_ascii=False, sort_keys=True))
        print("  actual:  ", json.dumps(actual, ensure_ascii=False, sort_keys=True))
    sys.exit(1)

print(f"Policy definition validated: {name}")
PY
}

create_or_validate_policy_definition() {
  local definition_name="$1"
  local policy_file="$2"

  [[ -f "$policy_file" ]] || {
    echo "ERROR: Policy file not found: $policy_file"
    exit 1
  }

  python3 -m json.tool "$policy_file" >/dev/null

  local existing_name
  existing_name=$(az policy definition list \
    --query "[?name=='$definition_name'].name | [0]" \
    -o tsv)

  if [[ -z "$existing_name" || "$existing_name" == "null" ]]; then
    echo
    echo "Policy definition missing. Creating: $definition_name"

    local definition_url
    local policy_file_win

    definition_url="https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.Authorization/policyDefinitions/$definition_name?api-version=$POLICY_DEFINITION_API_VERSION"
    policy_file_win="$(cygpath -w "$policy_file")"

    az_no_pathconv rest \
      --method put \
      --uri "$definition_url" \
      --body "@$policy_file_win" \
      -o none

    echo "Policy definition created."
  else
    echo
    echo "Policy definition already exists: $definition_name"
  fi

  validate_policy_definition "$definition_name" "$policy_file"
}

validate_policy_assignment() {
  local assignment_name="$1"
  local display_name="$2"
  local definition_name="$3"
  local parameters_json="$4"

  local live_file="$TMP_DIR/${assignment_name}.assignment.live.json"
  local expected_params_file="$TMP_DIR/${assignment_name}.params.expected.json"
  local definition_id="/subscriptions/$SUB_ID/providers/Microsoft.Authorization/policyDefinitions/$definition_name"

  printf '%s\n' "$parameters_json" > "$expected_params_file"

  az_no_pathconv policy assignment show \
    --name "$assignment_name" \
    --scope "$LAB_SCOPE" \
    -o json > "$live_file"

  python3 - \
    "$live_file" \
    "$expected_params_file" \
    "$assignment_name" \
    "$display_name" \
    "$SUB_ID" \
    "$RG_FINOPS_LAB" \
    "$definition_name" <<'PY'
import json
import sys

live_file, params_file, name, display_name, sub_id, rg_name, definition_name = sys.argv[1:8]

definition_id = f"/subscriptions/{sub_id}/providers/Microsoft.Authorization/policyDefinitions/{definition_name}"
scope = f"/subscriptions/{sub_id}/resourceGroups/{rg_name}"

with open(live_file, "r", encoding="utf-8-sig") as f:
    live = json.load(f)

with open(params_file, "r", encoding="utf-8-sig") as f:
    expected_params = json.load(f)

checks = {
    "displayName": (display_name, live.get("displayName")),
    "policyDefinitionId": (definition_id, live.get("policyDefinitionId")),
    "enforcementMode": ("Default", live.get("enforcementMode")),
    "parameters": (expected_params, live.get("parameters", {})),
    "scope": (scope, live.get("scope")),
}

drift = [(field, wanted, actual)
         for field, (wanted, actual) in checks.items()
         if wanted != actual]

if drift:
    print(f"ERROR: Policy assignment drift detected: {name}")
    for field, wanted, actual in drift:
        print(f"- {field}")
        print("  expected:", json.dumps(wanted, ensure_ascii=False, sort_keys=True))
        print("  actual:  ", json.dumps(actual, ensure_ascii=False, sort_keys=True))
    sys.exit(1)

print(f"Policy assignment validated: {name}")
PY
}

create_or_validate_policy_assignment() {
  local assignment_name="$1"
  local display_name="$2"
  local definition_name="$3"
  local parameters_json="$4"

  local definition_id="/subscriptions/$SUB_ID/providers/Microsoft.Authorization/policyDefinitions/$definition_name"

  echo
  echo "Processing policy assignment: $assignment_name"

  local existing_name
  existing_name=$(az_no_pathconv policy assignment list \
    --scope "$LAB_SCOPE" \
    --query "[?name=='$assignment_name'].name | [0]" \
    -o tsv)

  if [[ -z "$existing_name" || "$existing_name" == "null" ]]; then
    echo "Policy assignment missing. Creating..."

    az_no_pathconv policy assignment create \
      --name "$assignment_name" \
      --display-name "$display_name" \
      --scope "$LAB_SCOPE" \
      --policy "$definition_id" \
      --params "$parameters_json" \
      --enforcement-mode Default \
      -o none

    echo "Policy assignment created."
  else
    echo "Policy assignment already exists."
  fi

  validate_policy_assignment \
    "$assignment_name" \
    "$display_name" \
    "$definition_name" \
    "$parameters_json"
}

echo
echo "Validating or creating Module 04 custom policy definitions..."

create_or_validate_policy_definition \
  "finops-allowed-vm-sizes" \
  "$INFRA_DIR/allowed-vm-sizes.policy.json"

create_or_validate_policy_definition \
  "finops-deny-public-ip" \
  "$INFRA_DIR/deny-public-ip.policy.json"

create_or_validate_policy_definition \
  "finops-require-vm-autostop" \
  "$INFRA_DIR/require-vm-autostop-tag.policy.json"

create_or_validate_policy_definition \
  "finops-audit-governance-tags" \
  "$INFRA_DIR/audit-governance-tags.policy.json"

echo
echo "Validating or creating Module 04 policy assignments..."

create_or_validate_policy_assignment \
  "allowed-vm-sizes" \
  "Allow only approved VM sizes in lab" \
  "finops-allowed-vm-sizes" \
  '{
    "allowedVmSizes": {
      "value": [
        "Standard_B1s",
        "Standard_B2s"
      ]
    },
    "effect": {
      "value": "Deny"
    }
  }'

create_or_validate_policy_assignment \
  "deny-public-ip" \
  "Deny public IP addresses in lab" \
  "finops-deny-public-ip" \
  '{
    "effect": {
      "value": "Deny"
    }
  }'

create_or_validate_policy_assignment \
  "require-autostop-tag" \
  "Require AutoStop tag on lab VMs" \
  "finops-require-vm-autostop" \
  '{
    "tagName": {
      "value": "AutoStop"
    },
    "tagValue": {
      "value": "0200"
    },
    "effect": {
      "value": "Deny"
    }
  }'

create_or_validate_policy_assignment \
  "audit-governance-tags" \
  "Audit missing governance tags in lab" \
  "finops-audit-governance-tags" \
  '{
    "effect": {
      "value": "Audit"
    }
  }'

echo
echo "Deployment successful."
echo "Scope: $LAB_SCOPE"
echo
echo "Shared Foundation preserved:"
echo "- Resource Group: $RG_FINOPS_LAB"
echo "- Foundation governance tag values are consumed but not owned by Module 04"
echo
echo "Module 04 policy assignments:"

az_no_pathconv policy assignment list \
  --scope "$LAB_SCOPE" \
  --query "[?name=='allowed-vm-sizes' || name=='deny-public-ip' || name=='require-autostop-tag' || name=='audit-governance-tags'].{Name:name,PolicyDefinitionId:policyDefinitionId,EnforcementMode:enforcementMode}" \
  -o table

echo
echo "NOTE:"
echo "This script does not create, delete, or take ownership of the shared Resource Group."
echo "This script does not create or update Foundation governance tag values."
