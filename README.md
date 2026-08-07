# Azure FinOps & Governance Guardrails (CLI-first)

Practical Azure FinOps and governance guardrails built with **Azure CLI, Bicep, Azure Automation, Azure Policy, Managed Identity, RBAC, and proof-based validation**.

The goal of this repository is to build small, reproducible Azure governance modules that evolve step by step toward a lightweight, automated guardrail platform.

---

## Why this repo exists

I once built a Terraform skeleton and **forgot to tear it down**.

A budget alert helped me catch it early.

That experience led to a simple idea:

> Cloud cost control should not depend on remembering everything manually.

This repository follows that idea by adding multiple layers of protection:

```text
Budget visibility
+ Cost alerts
+ Runtime automation
+ Least-privilege RBAC
+ Tag governance
+ Preventive Azure Policy
+ Event-driven automation
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

The modules build on each other and represent an evolving FinOps and governance architecture rather than isolated demos.

---

## Modules

### 01 — Budget + Action Group (Alerts) ✅

Subscription-level budget alerts for early cost visibility.

### 02 — Nightly VM Auto-Stop ✅

Tag-based VM deallocation with Azure Automation, Managed Identity, and a custom RBAC role scoped to `rg-finops-lab`.

### 03 — Tag Governance Policy ✅

Azure Policy-based tag inheritance from `rg-finops-lab` to resources.

Governance metadata such as:

- Environment
- Project
- CostCenter
- Owner

is inherited automatically.

### 04 — Policy Baseline ✅

Preventive Azure Policy guardrails for:

- approved VM sizes
- denied public IP addresses
- required `AutoStop=0200` on VMs
- audited governance tags

Includes an extreme proof scenario using:

```text
Standard_M416ms_v2
```

which is blocked before the VM can be created.

### 05 — Event-Driven FinOps Guardrail 🚧 Planned

Resource creation triggers an event-driven workflow.

```text
Resource Creation
        ↓
Activity Log
        ↓
Event Grid
        ↓
Azure Function
        ↓
Evaluate resource
        ↓
Automatic governance action
```

### 06 — Terraform Guardrail Platform 🔜 Planned

All guardrails become reusable Terraform modules.

```text
terraform apply
        ↓
Budgets
Automation
RBAC
Tag Governance
Policy Baseline
Event-driven Guardrails
```

---

## Current Guardrails Evolution

```text
Module 01
Budget Alerts
        ↓
Early cost visibility

Module 02
AutoStop=0200
        ↓
Azure Automation Runbook
        ↓
Managed Identity
        ↓
Custom RBAC
        ↓
VM automatically deallocated

Module 03
Resource Group Tags
        ↓
Azure Policy
        ↓
Inherited governance tags
        ↓
Environment
Project
CostCenter
Owner

Module 04
Azure Policy Baseline
        ↓
Approved VM sizes
        ↓
Public IP denied
        ↓
AutoStop tag required
        ↓
Governance tags audited
        ↓
Risk prevented before deployment

Module 05
Resource created
        ↓
Activity Log
        ↓
Event Grid
        ↓
Azure Function
        ↓
Event-driven governance

Module 06
Terraform modules
        ↓
Single deployment
        ↓
Complete guardrail platform
```

---

## Guardrail Layers

```text
Visibility
    ↓
Budget Alerts

Operational Control
    ↓
Automation Runbooks

Identity
    ↓
Managed Identity

Least Privilege
    ↓
Custom RBAC

Governance
    ↓
Tag Inheritance

Prevention
    ↓
Azure Policy

Reaction
    ↓
Event-driven Automation

Platform
    ↓
Terraform
```

---

## Design Principles

- CLI-first
- Evidence-first
- Least privilege
- Scoped blast radius
- Prevent before reacting
- Automate repetitive governance
- Reusable building blocks
- Infrastructure evolves toward reusable Terraform modules

---

## Repository Structure

```text
modules/

├── 01-budget-alerts/
│   ├── infra/
│   ├── scripts/
│   ├── proofs/
│   └── README.md
│
├── 02-nightly-vm-autostop/
│   ├── infra/
│   ├── scripts/
│   ├── proofs/
│   └── README.md
│
├── 03-tag-governance-policy/
│   ├── scripts/
│   ├── proofs/
│   └── README.md
│
├── 04-policy-baseline/
│   ├── infra/
│   ├── scripts/
│   ├── proofs/
│   └── README.md
│
├── 05-event-driven-finops-guardrail/
│   ├── function/
│   ├── scripts/
│   ├── proofs/
│   └── README.md
│
└── 06-terraform-guardrail-platform/
    ├── modules/
    ├── environments/
    └── README.md
```

---

## Module Overview

| Module | Topic | Status |
|---------|-------|--------|
| 01 | Budget Alerts + Action Group | ✅ Completed |
| 02 | Nightly VM AutoStop with Managed Identity + Custom RBAC | ✅ Completed |
| 03 | Tag Governance with Azure Policy | ✅ Completed |
| 04 | Preventive Azure Policy Baseline | ✅ Completed |
| 05 | Event-Driven FinOps Guardrail | 🚧 Planned |
| 06 | Terraform Guardrail Platform | 🔜 Planned |

---

## Current Policy Baseline

The current Azure Policy baseline contains:

| Guardrail | Effect |
|-----------|--------|
| Allow approved VM sizes | Deny |
| Deny Public IP addresses | Deny |
| Require `AutoStop=0200` | Deny |
| Audit governance tags | Audit |

Approved VM sizes:

```text
Standard_B1s
Standard_B2s
```

Proof scenario:

```text
Deployment Attempt:
Standard_M416ms_v2

Result:
RequestDisallowedByPolicy

Created Resources:
[]
```

The resource never existed.

---

## Why this matters

Cloud governance is not only about detecting mistakes.

It is about making resources:

- visible
- attributable
- controlled
- auditable
- reproducible
- preventively governed
- automatically actionable

A VM should not simply exist.

It should answer:

```text
What environment does it belong to?
Which project does it support?
Who owns it?
Which cost center is responsible?
Which automation is allowed to manage it?
Which identity may perform that action?
Should this resource even be allowed to exist?
What should happen immediately after it is created?
```

This repository builds those answers step by step.

---

## Current Status

Implemented:

```text
✅ Module 01 — Budget Alerts
✅ Module 02 — Nightly VM AutoStop
✅ Module 03 — Tag Governance
✅ Module 04 — Azure Policy Baseline
```

Next evolution:

```text
🚧 Module 05 — Event-Driven Guardrails

🔜 Module 06 — Terraform Guardrail Platform
```

---

> Started as cost automation.  
> Evolved into governance.  
> Next step: fully event-driven, reusable guardrails.