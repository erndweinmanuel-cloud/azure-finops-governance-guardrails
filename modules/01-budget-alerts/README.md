# Module 01 — Budget + Alerts (Action Group) + Bicep

This module prevents unintended Azure costs by deploying:
- an Azure Monitor Action Group (email receiver)
- a monthly subscription budget (10 EUR) with notifications at 50/80/100%

## What you get
- Budget: **10 EUR / month**
- Duration: **2026-01-01 → 2031-01-01**
- Alerts: **50% / 80% / 100% actual spend**
- Target: Azure Monitor **Action Group** (`ag-budget-alerts`)

## Prerequisites
- Azure subscription
- Azure Cloud Shell (Bash)
- Permissions to create action groups + budgets

## Deploy (Cloud Shell / Bash)
```bash
cd modules/01-budget-alerts/scripts
bash ./deploy.sh
