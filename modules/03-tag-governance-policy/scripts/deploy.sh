#!/usr/bin/env bash
set -euo pipefail

# Run this script from Git Bash.
# Prevent Git Bash/MSYS from converting Azure resource IDs such as
# /subscriptions/... into local Windows paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

LOC="westeurope"

# Shared Foundation scope.
# Module 03 consumes this Resource Group but does not own or modify it.
RG_FINOPS_LAB="rg-finops-lab"

POLICY_DISPLAY_NAME="Inherit a tag from the resource group if missing"

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

echo "Subscription: $SUB_ID"
echo
echo "Validating shared Foundation Resource Group..."

if ! az group show \
  --name "$RG_FINOPS_LAB" \
  -o none; then
  echo "ERROR: Shared Foundation Resource Group not found: $RG_FINOPS_LAB"
  echo "Module 03 does not create Foundation Resource Groups."
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
    echo "Module 03 consumes Foundation tags but does not create or update them."
    exit 1
  fi

  echo "- $TAG_NAME=$TAG_VALUE"
done

echo
echo "Finding built-in Azure Policy definition:"
echo "$POLICY_DISPLAY_NAME"

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

  echo
  echo "Processing policy assignment: $ASSIGNMENT_NAME"
  echo "Tag: $TAG_NAME"

  local EXISTING_NAME
  EXISTING_NAME=$(az_no_pathconv policy assignment list \
    --scope "$LAB_SCOPE" \
    --query "[?name=='$ASSIGNMENT_NAME'].name | [0]" \
    -o tsv)

  if [[ -z "$EXISTING_NAME" || "$EXISTING_NAME" == "null" ]]; then
    echo "Policy assignment missing. Creating..."

    local PARAMS
    PARAMS="{\"tagName\":{\"value\":\"$TAG_NAME\"}}"

    az_no_pathconv policy assignment create \
      --name "$ASSIGNMENT_NAME" \
      --display-name "$DISPLAY_NAME" \
      --scope "$LAB_SCOPE" \
      --policy "$POLICY_DEF_ID" \
      --params "$PARAMS" \
      --mi-system-assigned \
      --location "$LOC" \
      --enforcement-mode Default \
      -o none

    echo "Policy assignment created."
  else
    echo "Policy assignment already exists. Validating semantic configuration..."

    local CURRENT_DISPLAY_NAME
    local CURRENT_POLICY_DEF_ID
    local CURRENT_TAG_NAME
    local CURRENT_IDENTITY_TYPE
    local CURRENT_LOCATION
    local CURRENT_ENFORCEMENT_MODE

    CURRENT_DISPLAY_NAME=$(az_no_pathconv policy assignment show \
      --name "$ASSIGNMENT_NAME" \
      --scope "$LAB_SCOPE" \
      --query displayName \
      -o tsv)

    CURRENT_POLICY_DEF_ID=$(az_no_pathconv policy assignment show \
      --name "$ASSIGNMENT_NAME" \
      --scope "$LAB_SCOPE" \
      --query policyDefinitionId \
      -o tsv)

    CURRENT_TAG_NAME=$(az_no_pathconv policy assignment show \
      --name "$ASSIGNMENT_NAME" \
      --scope "$LAB_SCOPE" \
      --query parameters.tagName.value \
      -o tsv)

    CURRENT_IDENTITY_TYPE=$(az_no_pathconv policy assignment show \
      --name "$ASSIGNMENT_NAME" \
      --scope "$LAB_SCOPE" \
      --query identity.type \
      -o tsv)

    CURRENT_LOCATION=$(az_no_pathconv policy assignment show \
      --name "$ASSIGNMENT_NAME" \
      --scope "$LAB_SCOPE" \
      --query location \
      -o tsv)

    CURRENT_ENFORCEMENT_MODE=$(az_no_pathconv policy assignment show \
      --name "$ASSIGNMENT_NAME" \
      --scope "$LAB_SCOPE" \
      --query enforcementMode \
      -o tsv)

    [[ "$CURRENT_DISPLAY_NAME" == "$DISPLAY_NAME" ]] || {
      echo "ERROR: Display name drift detected for $ASSIGNMENT_NAME"
      echo "Expected: $DISPLAY_NAME"
      echo "Actual:   $CURRENT_DISPLAY_NAME"
      exit 1
    }

    [[ "$CURRENT_POLICY_DEF_ID" == "$POLICY_DEF_ID" ]] || {
      echo "ERROR: Policy definition drift detected for $ASSIGNMENT_NAME"
      echo "Expected: $POLICY_DEF_ID"
      echo "Actual:   $CURRENT_POLICY_DEF_ID"
      exit 1
    }

    [[ "$CURRENT_TAG_NAME" == "$TAG_NAME" ]] || {
      echo "ERROR: tagName parameter drift detected for $ASSIGNMENT_NAME"
      echo "Expected: $TAG_NAME"
      echo "Actual:   $CURRENT_TAG_NAME"
      exit 1
    }

    [[ "$CURRENT_IDENTITY_TYPE" == "SystemAssigned" ]] || {
      echo "ERROR: Managed Identity drift detected for $ASSIGNMENT_NAME"
      echo "Expected: SystemAssigned"
      echo "Actual:   $CURRENT_IDENTITY_TYPE"
      exit 1
    }

    [[ "${CURRENT_LOCATION,,}" == "${LOC,,}" ]] || {
      echo "ERROR: Location drift detected for $ASSIGNMENT_NAME"
      echo "Expected: $LOC"
      echo "Actual:   $CURRENT_LOCATION"
      exit 1
    }

    [[ "$CURRENT_ENFORCEMENT_MODE" == "Default" ]] || {
      echo "ERROR: Enforcement mode drift detected for $ASSIGNMENT_NAME"
      echo "Expected: Default"
      echo "Actual:   $CURRENT_ENFORCEMENT_MODE"
      exit 1
    }

    echo "Policy assignment validated."
  fi

  echo "Resolving policy assignment Managed Identity..."

  local ASSIGNMENT_PRINCIPAL_ID=""

  for i in {1..24}; do
    ASSIGNMENT_PRINCIPAL_ID=$(az_no_pathconv policy assignment show \
      --name "$ASSIGNMENT_NAME" \
      --scope "$LAB_SCOPE" \
      --query identity.principalId \
      -o tsv)

    if [[ -n "$ASSIGNMENT_PRINCIPAL_ID" && "$ASSIGNMENT_PRINCIPAL_ID" != "null" ]]; then
      break
    fi

    echo "Waiting for Managed Identity principalId... ($i/24)"
    sleep 5
  done

  [[ -n "$ASSIGNMENT_PRINCIPAL_ID" && "$ASSIGNMENT_PRINCIPAL_ID" != "null" ]] || {
    echo "ERROR: No Managed Identity principalId found for assignment: $ASSIGNMENT_NAME"
    exit 1
  }

  echo "Managed Identity Principal ID: $ASSIGNMENT_PRINCIPAL_ID"
  echo "Validating Tag Contributor role assignment..."

  local ROLE_ASSIGNMENT_ID
  ROLE_ASSIGNMENT_ID=$(az_no_pathconv role assignment list \
    --role "Tag Contributor" \
    --scope "$LAB_SCOPE" \
    --query "[?principalId=='$ASSIGNMENT_PRINCIPAL_ID' && scope=='$LAB_SCOPE'].id | [0]" \
    -o tsv)

  if [[ -z "$ROLE_ASSIGNMENT_ID" || "$ROLE_ASSIGNMENT_ID" == "null" ]]; then
    echo "Tag Contributor role assignment missing. Creating..."

    local ROLE_CREATED="false"

    for i in {1..12}; do
      if az_no_pathconv role assignment create \
        --assignee-object-id "$ASSIGNMENT_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Tag Contributor" \
        --scope "$LAB_SCOPE" \
        -o none; then
        ROLE_CREATED="true"
        break
      fi

      echo "Role assignment creation not ready yet. Retrying... ($i/12)"
      sleep 5
    done

    [[ "$ROLE_CREATED" == "true" ]] || {
      echo "ERROR: Failed to create Tag Contributor role assignment."
      exit 1
    }

    echo "Tag Contributor role assignment created."
  else
    echo "Tag Contributor role assignment already exists."
  fi

  local CONFIRMED_ROLE_ASSIGNMENT_ID
  CONFIRMED_ROLE_ASSIGNMENT_ID=$(az_no_pathconv role assignment list \
    --role "Tag Contributor" \
    --scope "$LAB_SCOPE" \
    --query "[?principalId=='$ASSIGNMENT_PRINCIPAL_ID' && scope=='$LAB_SCOPE'].id | [0]" \
    -o tsv)

  [[ -n "$CONFIRMED_ROLE_ASSIGNMENT_ID" && "$CONFIRMED_ROLE_ASSIGNMENT_ID" != "null" ]] || {
    echo "ERROR: Tag Contributor role assignment could not be confirmed."
    exit 1
  }

  echo "Tag Contributor role assignment confirmed."
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
echo "Scope: $LAB_SCOPE"
echo
echo "Shared Foundation preserved:"
echo "- Resource Group: $RG_FINOPS_LAB"
echo "- Governance tag values are consumed but not owned by Module 03"
echo
echo "Module 03 policy assignments:"

az_no_pathconv policy assignment list \
  --scope "$LAB_SCOPE" \
  --query "[?starts_with(name, 'inherit-')].{Name:name,TagName:parameters.tagName.value,PrincipalId:identity.principalId,IdentityType:identity.type,Location:location,EnforcementMode:enforcementMode}" \
  -o table

echo
echo "NOTE:"
echo "This script does not create, delete, or take ownership of the shared Resource Group."
echo "This script does not create or update Foundation governance tag values."
