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

POLICY_DISPLAY_NAME="Inherit a tag from the resource group if missing"
POLICY_ASSIGNMENT_API_VERSION="2022-06-01"

SUB_ID=$(az account show --query id -o tsv)
LAB_SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG_FINOPS_LAB"

echo "Creating or updating Resource Group: $RG_FINOPS_LAB"

az group create \
  --name "$RG_FINOPS_LAB" \
  --location "$LOC" \
  -o none

echo "Setting central Resource Group tags..."

az group update \
  --name "$RG_FINOPS_LAB" \
  --set \
    tags.Environment="$TAG_ENVIRONMENT" \
    tags.Project="$TAG_PROJECT" \
    tags.CostCenter="$TAG_COSTCENTER" \
    tags.Owner="$TAG_OWNER" \
  -o none

echo "Finding built-in Azure Policy definition: $POLICY_DISPLAY_NAME"

POLICY_DEF_ID=$(az policy definition list \
  --query "[?displayName=='$POLICY_DISPLAY_NAME'].id | [0]" \
  -o tsv)

[[ -n "$POLICY_DEF_ID" && "$POLICY_DEF_ID" != "null" ]] || {
  echo "ERROR: Policy definition not found: $POLICY_DISPLAY_NAME"
  exit 1
}

echo "Policy definition found:"
echo "$POLICY_DEF_ID"

create_or_validate_assignment() {
  local TAG_NAME="$1"
  local ASSIGNMENT_NAME="$2"
  local DISPLAY_NAME="$3"

  local ASSIGNMENT_URL
  ASSIGNMENT_URL="https://management.azure.com${LAB_SCOPE}/providers/Microsoft.Authorization/policyAssignments/${ASSIGNMENT_NAME}?api-version=${POLICY_ASSIGNMENT_API_VERSION}"

  local BODY
  BODY=$(cat <<JSON
{
  "location": "$LOC",
  "identity": {
    "type": "SystemAssigned"
  },
  "properties": {
    "displayName": "$DISPLAY_NAME",
    "policyDefinitionId": "$POLICY_DEF_ID",
    "parameters": {
      "tagName": {
        "value": "$TAG_NAME"
      }
    }
  }
}
JSON
)

  echo
  echo "Processing policy assignment: $ASSIGNMENT_NAME"
  echo "Tag: $TAG_NAME"

  if az_no_pathconv rest \
    --method get \
    --url "$ASSIGNMENT_URL" \
    -o none 2>/dev/null; then

    echo "Policy assignment already exists: $ASSIGNMENT_NAME"
  else
    echo "Creating policy assignment: $ASSIGNMENT_NAME"

    az_no_pathconv rest \
      --method put \
      --url "$ASSIGNMENT_URL" \
      --headers "Content-Type=application/json" \
      --body "$BODY" \
      -o none
  fi

  echo "Reading policy assignment managed identity..."

  ASSIGNMENT_PRINCIPAL_ID=""

  for i in {1..24}; do
    ASSIGNMENT_PRINCIPAL_ID=$(az_no_pathconv rest \
      --method get \
      --url "$ASSIGNMENT_URL" \
      --query identity.principalId \
      -o tsv 2>/dev/null || true)

    if [[ -n "$ASSIGNMENT_PRINCIPAL_ID" && "$ASSIGNMENT_PRINCIPAL_ID" != "null" ]]; then
      break
    fi

    sleep 5
  done

  if [[ -n "$ASSIGNMENT_PRINCIPAL_ID" && "$ASSIGNMENT_PRINCIPAL_ID" != "null" ]]; then
    echo "Managed Identity Principal ID: $ASSIGNMENT_PRINCIPAL_ID"
    echo "Ensuring Tag Contributor role for policy assignment identity..."

    az_no_pathconv role assignment create \
      --assignee-object-id "$ASSIGNMENT_PRINCIPAL_ID" \
      --assignee-principal-type ServicePrincipal \
      --role "Tag Contributor" \
      --scope "$LAB_SCOPE" \
      -o none 2>/dev/null || true
  else
    echo "ERROR: No managed identity principalId found for assignment: $ASSIGNMENT_NAME"
    exit 1
  fi
}

create_or_validate_assignment \
  "Environment" \
  "inherit-environment-tag" \
  "Inherit Environment tag from resource group if missing"

create_or_validate_assignment \
  "Project" \
  "inherit-project-tag" \
  "Inherit Project tag from resource group if missing"

create_or_validate_assignment \
  "CostCenter" \
  "inherit-costcenter-tag" \
  "Inherit CostCenter tag from resource group if missing"

create_or_validate_assignment \
  "Owner" \
  "inherit-owner-tag" \
  "Inherit Owner tag from resource group if missing"

echo
echo "Deployment successful."
echo "Resource Group: $RG_FINOPS_LAB"
echo "Scope: $LAB_SCOPE"
echo
echo "Central Resource Group tags:"
az group show \
  --name "$RG_FINOPS_LAB" \
  --query tags \
  -o jsonc

echo
echo "Policy assignments:"
az_no_pathconv rest \
  --method get \
  --url "https://management.azure.com${LAB_SCOPE}/providers/Microsoft.Authorization/policyAssignments?api-version=${POLICY_ASSIGNMENT_API_VERSION}" \
  --query "value[?starts_with(name, 'inherit-')].{Name:name,DisplayName:properties.displayName,PrincipalId:identity.principalId}" \
  -o table