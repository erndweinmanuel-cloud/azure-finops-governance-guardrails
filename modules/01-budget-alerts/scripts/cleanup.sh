#!/usr/bin/env bash
set -euo pipefail

RG_OPS="rg-ops-guardrails"
AG_NAME="ag-budget-alerts"
BUDGET_NAME="budget-monthly"

echo "Cleaning up Module 01 resources..."

# Delete subscription budget if it exists.
if az consumption budget show \
  --budget-name "$BUDGET_NAME" \
  -o none 2>/dev/null; then

  echo "Deleting budget: $BUDGET_NAME"

  az consumption budget delete \
    --budget-name "$BUDGET_NAME"
else
  echo "Budget not found: $BUDGET_NAME"
fi

# Delete Action Group if it exists.
if az monitor action-group show \
  --resource-group "$RG_OPS" \
  --name "$AG_NAME" \
  -o none 2>/dev/null; then

  echo "Deleting Action Group: $AG_NAME"

  az monitor action-group delete \
    --resource-group "$RG_OPS" \
    --name "$AG_NAME"
else
  echo "Action Group not found: $AG_NAME"
fi

echo
echo "Module 01 cleanup completed."
echo "Shared resource group preserved: $RG_OPS"
