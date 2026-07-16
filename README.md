# Azure FinOps & Governance Guardrails (CLI-first)

Practical guardrails to prevent unintended Azure costs and establish baseline governance — built with **Azure CLI, Bicep, Azure Automation, Azure Policy, and proof-based validation**.

The goal of this repository is to build small, reproducible Azure governance modules that can evolve toward a lightweight Landing Zone foundation.

---

## Why this repo exists

I once built a Terraform skeleton and **forgot to tear it down**.

A budget alert helped me catch it early.

Result: I decided to implement **layered safety nets** so forgotten resources do not turn into surprise bills.

This repository follows that idea:

```text
Budget visibility
+ Cost alerts
+ Runtime automation
+ Least-privilege RBAC
+ Tag governance
+ Policy-based guardrails
```

---

## What’s inside

This repo is organized as **modules**.

Each module is a standalone mini-project with:

- reproducible deployment steps
- cleanup or rollback considerations
- proof artifacts
- screenshots and/or CLI evidence
- a dedicated `README.md`

The modules are designed to build on each other instead of being isolated demos.

---

## Modules

1. **01 — Budget + Action Group (Alerts)** ✅
   Subscription-level budget alerts for early cost visibility.

2. **02 — Nightly VM Auto-Stop** ✅
   Tag-based VM deallocation with Azure Automation, Managed Identity, and a custom RBAC role scoped to `rg-finops-lab`.

3. **03 — Tag Governance Policy** ✅
   Azure Policy-based tag inheritance from `rg-finops-lab` to resources. Validated with the AutoStop VM scenario from Module 02.

4. **04 — Policy Baseline** *(later)*
   Planned baseline guardrails such as allowed regions, required tags, expensive VM restrictions, and public IP restrictions.

5. **05 — Event-Driven / CreatedBy Tagging** *(later)*
   Planned event-driven tagging using Activity Log, Event Grid, and Azure Functions to add dynamic creator/accountability metadata.

---

## Current Guardrails Evolution

```text
Module 01:
Budget Alerts
        ↓
Early cost visibility

Module 02:
AutoStop=0200
        ↓
Azure Automation Runbook
        ↓
Managed Identity
        ↓
Custom RBAC on Resource Group scope
        ↓
VM deallocated with least privilege

Module 03:
Resource Group governance tags
        ↓
Azure Policy tag inheritance
        ↓
VM receives Environment, Project, CostCenter, Owner
        ↓
AutoStop automation still works
```

Together, the modules demonstrate:

```text
Cost visibility
+ Operational control
+ Least-privilege execution
+ Governance context
+ Evidence-based validation
```

---

## Design Principles

- **CLI-first**: Azure Portal is used mainly for validation and screenshots.
- **Evidence-first**: each module includes proof artifacts under `proofs/`.
- **Least privilege**: automation identities should receive only the permissions they need.
- **Scoped blast radius**: guardrails are tested on dedicated resource groups.
- **Guardrails > Hope**: assume someone will forget a resource at 2am and automate safety.
- **Reusable patterns**: small lab modules should be transferable to larger environments.

---

## Repo Structure

```text
modules/
  01-budget-alerts/
    infra/        # Bicep
    scripts/      # Deployment scripts
    proofs/       # JSONC outputs + screenshots
    README.md

  02-nightly-vm-autostop/
    infra/        # Runbook + custom RBAC role definition
    scripts/      # Deployment and cleanup scripts
    proofs/       # V1 and V1.1 validation artifacts
    README.md

  03-tag-governance-policy/
    scripts/      # Azure Policy assignment deployment
    proofs/       # CLI evidence + screenshots
    README.md
```

---

## Module Overview

| Module | Topic | Status |
| -----: | ----- | ------ |
| 01 | Budget Alerts + Action Group | ✅ Completed |
| 02 | Nightly VM AutoStop with Managed Identity + Custom RBAC | ✅ Completed |
| 03 | Tag Governance with Azure Policy | ✅ Completed |
| 04 | Policy Baseline | Planned |
| 05 | Event-Driven CreatedBy Tagging | Planned |

---

## Why this matters

Cloud governance is not only about preventing mistakes.

It is about making resources:

- visible
- attributable
- controlled
- auditable
- reproducible

A VM should not just exist.

It should answer:

```text
What environment does it belong to?
Which project does it support?
Who owns it?
Which cost bucket is it assigned to?
Which automation is allowed to act on it?
Which identity is allowed to perform that action?
```

This repository builds those answers step by step.

---

## Status

This repository currently contains three implemented modules:

```text
01 Budget Alerts
02 Nightly VM AutoStop with least-privilege RBAC
03 Tag Governance with Azure Policy
```

The next planned evolution is a small Azure Policy baseline and later event-driven `CreatedBy` tagging.

> Started as cost automation. Evolved into a governance control.
