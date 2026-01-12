#!/usr/bin/env bash
set -euo pipefail

LOC="westeurope"
RG_OPS="rg-ops-guardrails"
AG_NAME="ag-budget-alerts"
EMAIL="erndweinmanuel@gmail.com"

BUDGET_NAME="budget-monthly"
AMOUNT=10
START_DATE="2026-01-01"
END_DATE="2031-01-01"

az group create -n "$RG_OPS" -l "$LOC" -o table

az monitor action-group create \
  -g "$RG_OPS" -n "$AG_NAME" --short-name budget \
  --location global \
  --action email me "$EMAIL"

AG_ID=$(az monitor action-group show -g "$RG_OPS" -n "$AG_NAME" --query id -o tsv)

az deployment sub create \
  -l "$LOC" \
  -n "dep-budget-$(date +%Y%m%d%H%M%S)" \
  -f "../infra/budget.bicep" \
  -p budgetName="$BUDGET_NAME" amount=$AMOUNT startDate="$START_DATE" endDate="$END_DATE" actionGroupId="$AG_ID"

az consumption budget show --budget-name "$BUDGET_NAME" -o jsonc
