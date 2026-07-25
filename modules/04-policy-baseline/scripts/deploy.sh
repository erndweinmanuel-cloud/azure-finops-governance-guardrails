#!/usr/bin/env bash
set -euo pipefail

# Run this script from Git Bash.
# Prevent Git Bash from converting Azure resource IDs such as /subscriptions/... into local paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

LOC="westeurope"
RG_FINOPS_LAB="rg-finops-lab"

TAG_ENVIRONMENT="Lab"
TAG_PROJECT="FinOpsGuardrails"
TAG_COSTCENTER="FinOpsLab"
TAG_OWNER="Manuel"

POLICY_DEFINITION_API_VERSION="2021-06-01"
POLICY_ASSIGNMENT_API_VERSION="2022-06-01"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$MODULE_DIR/infra"

SUB_ID="$(az account show --query id -o tsv)"
LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "Creating or updating Resource Group: $RG_FINOPS_LAB"

az group create \
  --name "$RG_FINOPS_LAB" \
  --location "$LOC" \
  -o none

echo "Setting central Resource Group tags..."

az group update \
  --name "$RG_FINOPS_LAB" \
  --set tags.Environment="$TAG_ENVIRONMENT" \
        tags.Project="$TAG_PROJECT" \
        tags.CostCenter="$TAG_COSTCENTER" \
        tags.Owner="$TAG_OWNER" \
  -o none

create_policy_definition() {
  local definition_name="$1"
  local policy_file="$2"

  local definition_url="https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.Authorization/policyDefinitions/$definition_name?api-version=$POLICY_DEFINITION_API_VERSION"
  local policy_file_win
  policy_file_win="$(cygpath -w "$policy_file")"

  echo "Creating or updating policy definition: $definition_name"

  az_no_pathconv rest \
    --method put \
    --uri "$definition_url" \
    --body "@$policy_file_win" \
    -o none
}

create_policy_assignment() {
  local assignment_name="$1"
  local display_name="$2"
  local definition_name="$3"
  local parameters_json="$4"

  local assignment_url="https://management.azure.com${LAB_SCOPE}/providers/Microsoft.Authorization/policyAssignments/${assignment_name}?api-version=${POLICY_ASSIGNMENT_API_VERSION}"
  local definition_id="/subscriptions/$SUB_ID/providers/Microsoft.Authorization/policyDefinitions/$definition_name"

  local temp_body
  temp_body="$(mktemp)"

  cat > "$temp_body" <<EOF
{
  "properties": {
    "displayName": "$display_name",
    "policyDefinitionId": "$definition_id",
    "parameters": $parameters_json
  }
}
EOF

  local temp_body_win
  temp_body_win="$(cygpath -w "$temp_body")"

  echo "Creating or updating policy assignment: $assignment_name"

  az_no_pathconv rest \
    --method put \
    --uri "$assignment_url" \
    --body "@$temp_body_win" \
    -o none

  rm -f "$temp_body"
}

echo "Creating custom policy definitions..."

create_policy_definition \
  "finops-allowed-vm-sizes" \
  "$INFRA_DIR/allowed-vm-sizes.policy.json"

create_policy_definition \
  "finops-deny-public-ip" \
  "$INFRA_DIR/deny-public-ip.policy.json"

create_policy_definition \
  "finops-require-vm-autostop" \
  "$INFRA_DIR/require-vm-autostop-tag.policy.json"

create_policy_definition \
  "finops-audit-governance-tags" \
  "$INFRA_DIR/audit-governance-tags.policy.json"

echo "Creating policy assignments on scope: $LAB_SCOPE"

create_policy_assignment \
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

create_policy_assignment \
  "deny-public-ip" \
  "Deny public IP addresses in lab" \
  "finops-deny-public-ip" \
  '{
    "effect": {
      "value": "Deny"
    }
  }'

create_policy_assignment \
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

create_policy_assignment \
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
echo "Resource Group: $RG_FINOPS_LAB"
echo "Scope: $LAB_SCOPE"
echo

echo "Central Resource Group tags:"
az group show \
  --name "$RG_FINOPS_LAB" \
  --query "{name:name,tags:tags}" \
  -o jsonc

echo
echo "Policy assignments:"
az_no_pathconv rest \
  --method get \
  --uri "https://management.azure.com${LAB_SCOPE}/providers/Microsoft.Authorization/policyAssignments?api-version=${POLICY_ASSIGNMENT_API_VERSION}" \
  --query "value[].{name:name,displayName:properties.displayName,policyDefinitionId:properties.policyDefinitionId}" \
  -o table