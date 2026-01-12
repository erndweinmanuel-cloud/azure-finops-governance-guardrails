# Azure FinOps & Governance Guardrails (CLI-first)

Practical guardrails to prevent unintended Azure costs and establish baseline governance — built with **Azure CLI + Bicep**, designed to be **reproducible** and **Landing Zone-ready**.

## Why this repo exists (real-world trigger)
I once built a Terraform skeleton and **forgot to tear it down**. A budget alert helped me catch it early.
Result: I decided to implement **layered safety nets** (Budget + Alerts + Automation + Policy) so “forgotten resources” don’t turn into surprise bills.

## What’s inside
This repo is organized as **modules**. Each module is a standalone mini-project with:
- reproducible deployment steps
- cleanup steps
- proofs (CLI outputs / screenshots)

## Modules
1. **01 — Budget + Action Group (Alerts)** ✅
2. **02 — Nightly VM Auto-Stop (Automation + Managed Identity)** *(next)*
3. **03 — Policy Baseline (Landing Zone-ready)** *(later)*

## Design principles
- **CLI-first**: minimal portal usage
- **Evidence-first**: every module includes `proofs/`
- **Guardrails > Hope**: assume you will forget something at 2am → automate safety

## Repo structure
```text
modules/
  01-budget-alerts/
    infra/        # Bicep
    scripts/      # Bash (Azure Cloud Shell)
    proofs/       # JSONC outputs + screenshots
    README.md
```     
