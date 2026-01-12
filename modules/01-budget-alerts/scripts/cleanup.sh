#!/usr/bin/env bash
set -euo pipefail

RG_OPS="rg-ops-guardrails"
AG_NAME="ag-budget-alerts"
BUDGET_NAME="budget-monthly"

az consumption budget delete --budget-name "$BUDGET_NAME" 2>/dev/null || true
az monitor action-group delete -g "$RG_OPS" -n "$AG_NAME" 2>/dev/null || true
az group delete -n "$RG_OPS" --yes --no-wait 2>/dev/null || true
