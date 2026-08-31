#!/usr/bin/env bash
set -euo pipefail

# Prevent Git Bash from converting Azure resource IDs such as
# /subscriptions/... into Windows paths.
az_no_pathconv() {
  MSYS_NO_PATHCONV=1 az "$@"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LOC="westeurope"

RG_OPS="rg-ops-guardrails"
AG_NAME="ag-budget-alerts"

BUDGET_NAME="budget-monthly"
AMOUNT=10
START_DATE="2026-01-01"
END_DATE="2031-01-01"

BUDGET_API_VERSION="2024-08-01"

BICEP_FILE="$MODULE_DIR/infra/budget.bicep"
BICEP_FILE_AZ="$(cygpath -w "$BICEP_FILE")"

EMAIL="${BUDGET_ALERT_EMAIL:?Set BUDGET_ALERT_EMAIL before running this script}"

SUB_ID=$(az account show --query id -o tsv)

echo "Deploying Module 01 - Budget Alerts..."
echo

echo "Creating or validating shared resource group: $RG_OPS"
az group create \
  --name "$RG_OPS" \
  --location "$LOC" \
  -o none

echo "Creating or updating Action Group: $AG_NAME"
az monitor action-group create \
  --resource-group "$RG_OPS" \
  --name "$AG_NAME" \
  --short-name budget \
  --location global \
  --action email me "$EMAIL" \
  -o none

AG_ID=$(az monitor action-group show \
  --resource-group "$RG_OPS" \
  --name "$AG_NAME" \
  --query id \
  -o tsv)

[[ -n "$AG_ID" ]] || {
  echo "ERROR: Action Group ID could not be resolved."
  exit 1
}

echo "Action Group ID: $AG_ID"

echo
echo "Creating or updating subscription budget: $BUDGET_NAME"

az_no_pathconv deployment sub create \
  --location "$LOC" \
  --name "dep-budget-$(date +%Y%m%d%H%M%S)" \
  --template-file "$BICEP_FILE_AZ" \
  --parameters \
    budgetName="$BUDGET_NAME" \
    amount="$AMOUNT" \
    startDate="$START_DATE" \
    endDate="$END_DATE" \
    actionGroupId="$AG_ID" \
  -o none

BUDGET_URL="https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.Consumption/budgets/$BUDGET_NAME?api-version=$BUDGET_API_VERSION"

echo
echo "Validating Budget -> Action Group dependencies..."

for THRESHOLD in 50 80 100; do
  CONTACT_GROUP=$(az rest \
    --method get \
    --url "$BUDGET_URL" \
    --query "properties.notifications.actual_GTE_${THRESHOLD}.contactGroups[0]" \
    -o tsv)

  EXPECTED=$(echo "$AG_ID" | tr '[:upper:]' '[:lower:]')
  ACTUAL=$(echo "$CONTACT_GROUP" | tr '[:upper:]' '[:lower:]')

  if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    echo "ERROR: Budget threshold ${THRESHOLD}% does not reference the expected Action Group."
    echo "Expected: $AG_ID"
    echo "Actual:   $CONTACT_GROUP"
    exit 1
  fi

  echo "OK: ${THRESHOLD}% -> $AG_NAME"
done

echo
echo "Validating Action Group email receiver..."

RECEIVER_STATUS=$(az monitor action-group show \
  --resource-group "$RG_OPS" \
  --name "$AG_NAME" \
  --query "emailReceivers[0].status" \
  -o tsv)

if [[ "$RECEIVER_STATUS" != "Enabled" ]]; then
  echo "ERROR: Action Group email receiver is not enabled."
  exit 1
fi

echo "OK: Email receiver enabled"

echo
echo "Module 01 deployment successful."
echo "Budget:       $BUDGET_NAME"
echo "Amount:       $AMOUNT EUR / month"
echo "Action Group: $AG_NAME"
echo "Thresholds:   50% / 80% / 100%"
echo
echo "Shared resource group preserved: $RG_OPS"