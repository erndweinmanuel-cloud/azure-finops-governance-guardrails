# Module 01 — Budget + Alerts (Action Group) + Bicep

This module prevents unintended Azure costs by deploying:
- an Azure Monitor **Action Group** (email receiver)
- a monthly **subscription budget** (10 EUR) with notifications at 50/80/100%

## Why it matters (short real story)
I previously forgot to tear down a lab environment. A budget alert caught it early.
This module is the first permanent safety net: **budget + notifications** so cost surprises don’t happen.

## What you get
- Budget: **10 EUR / month**
- Duration: **2026-01-01 → 2031-01-01** (5 years)
- Alerts: **50% / 80% / 100% actual spend**
- Notification target: Azure Monitor **Action Group** (`ag-budget-alerts`)
- Scope: **Subscription** (`budget-monthly`)

## Tech
- Azure CLI (Cloud Shell Bash)
- Bicep (subscription-scope deployment)

## Prerequisites
- Azure subscription
- Azure Cloud Shell **Bash**
- Permission to create action groups + budgets

## Deploy (Cloud Shell / Bash)
```bash
cd modules/01-budget-alerts/scripts
bash ./deploy.sh
```

## Verify (quick checks)
```bash
az monitor action-group show -g rg-ops-guardrails -n ag-budget-alerts -o table

SUB=$(az account show --query id -o tsv)
az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Consumption/budgets?api-version=2024-08-01" \
  -o jsonc
```

## Proofs (evidence)

CLI outputs:
- `proofs/action-group.ag-budget-alerts.jsonc`
- `proofs/budget.budget-monthly.jsonc`

Email evidence (redacted screenshots):
- `proofs/screenshots/budget-alert_redacted_v3.jpeg`
- `proofs/screenshots/action-group-added_redacted_v2.jpeg`

## Notes

- Action Groups require `--location global` (resource-type constraint).
- Budget is created via ARM REST/Bicep because `az consumption budget` is preview and can be inconsistent depending on context.
