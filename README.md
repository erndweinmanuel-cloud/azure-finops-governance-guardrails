# Azure FinOps & Governance Guardrails

Practical Azure FinOps and governance guardrails built with **Azure CLI, Azure Automation, Azure Policy, Microsoft Entra ID, Managed Identity, RBAC, Event Grid, Azure Functions, and proof-based validation**.

The repository evolves step by step from simple cost visibility toward a small governed Azure platform with preventive controls, workload boundaries, automated resource attribution, and eventually Terraform-managed desired state.

---

## Why This Repo Exists

I once built a Terraform lab environment and forgot to tear it down.

A budget alert helped me catch it early.

That experience led to a simple idea:

> Cloud cost control should not depend on remembering everything manually.

The project therefore evolved through multiple guardrail layers:

```text
Cost Visibility
      +
Runtime Automation
      +
Least-Privilege RBAC
      +
Tag Governance
      +
Preventive Azure Policy
      +
Event-Driven Attribution
      +
Infrastructure as Code
```

The objective is not to build isolated Azure demos.

The objective is to make the individual controls work together as a small governance platform.

---

# Modules

## 01 — Budget Alerts ✅

Subscription-level Azure Cost Management budget alerts provide early cost visibility.

Core idea:

```text
Azure Spending
      ↓
Budget Threshold
      ↓
Action Group
      ↓
Notification
```

The first guardrail is simple:

**detect unexpected cost before it becomes expensive.**

---

## 02 — Nightly VM AutoStop ✅

Tag-based VM deallocation using:

- Azure Automation
- System-assigned Managed Identity
- Custom RBAC
- Resource Group scope
- `AutoStop=0200`

Architecture:

```text
VM
 |
 | AutoStop=0200
 v
Azure Automation Runbook
 |
 v
Managed Identity
 |
 v
Custom Least-Privilege RBAC
 |
 v
VM Deallocated
```

The automation can manage intended VM lifecycle actions without broad subscription permissions.

---

## 03 — Tag Governance Policy ✅

Central governance metadata is defined on:

```text
rg-finops-lab
```

Resource Group tags:

```text
Environment = Lab
Project     = FinOpsGuardrails
CostCenter  = FinOpsLab
Owner       = Manuel
```

Azure Policy `Modify` assignments inherit missing governance tags onto resources.

This makes resources easier to classify by:

- environment
- project
- cost center
- responsibility

---

## 04 — Preventive Policy Baseline ✅

Azure Policy adds preventive guardrails before risky resources can exist.

Current controls include:

| Guardrail | Effect |
|---|---|
| Allow approved VM sizes | Deny |
| Deny Public IP addresses | Deny |
| Require `AutoStop=0200` | Deny |
| Audit governance tags | Audit |

Approved VM sizes:

```text
Standard_B1s
Standard_B2s
```

A deployment outside that allowlist is blocked with:

```text
RequestDisallowedByPolicy
```

The important shift is:

```text
Reactive FinOps
"Why did this cost money?"

        ↓

Preventive FinOps
"Should this resource have been allowed to exist?"
```

---

# 05 — Event-Driven Resource Attribution ✅

Module 05 adds dynamic accountability to the governance platform.

Instead of only knowing what project or cost center a resource belongs to, the platform now automatically records **who actually created it**.

Automatic tags:

```text
CreatedBy
CreatedByType
CreatedAt
```

The implementation uses:

- Microsoft Entra ID
- Group-based RBAC
- Custom workload role
- Azure Policy
- Azure Activity Log events
- Azure Event Grid
- Azure Functions
- System-assigned Managed Identity
- Custom least-privilege tagging role

---

## Module 05 Architecture

```text
Engineer Identity
        |
        v
Entra ID Security Group
        |
        v
Custom Azure RBAC Role
        |
        v
Azure Policy Guardrails
        |
        v
Resource Creation
        |
        +-------------------------------+
        |                               |
        v                               v
Tag Governance                  ResourceWriteSuccess
        |                               |
        v                               v
Environment                     Event Grid
Project                             |
CostCenter                          v
Owner                         Azure Function
                                    |
                                    v
                             Managed Identity
                                    |
                                    v
                       Custom Tagging RBAC Role
                                    |
                                    v
                               Azure Resource
                                    |
                +-------------------+-------------------+
                |                                       |
                v                                       v
        Governance Metadata                      Attribution

        Environment                              CreatedBy
        Project                                  CreatedByType
        CostCenter                               CreatedAt
        Owner

                +
           AutoStop=0200
                +
          No Public IP
```

---

## Identity and Blast-Radius Model

The lab deliberately separates platform administration from workload engineering.

### Engineers

Security group:

```text
grp-azure-finops-lab-engineers
```

Custom role:

```text
FinOps Lab VM Engineer
```

Engineers can:

- deploy approved VMs
- manage intended VM lifecycle operations
- create and use NICs
- join existing subnets
- read existing network infrastructure

They cannot manage the lifecycle of the platform VNet.

Example validation:

```text
Delete VM
→ Allowed

Delete Platform VNet
→ AuthorizationFailed
```

This keeps workload self-service while limiting the blast radius.

### Reader / Auditor

The read-only identity receives:

```text
Reader
```

Validation:

```text
Read VNet
→ Allowed

Create Storage Account
→ AuthorizationFailed
```

---

## Event-Driven Attribution

The core Module 05 flow is:

```text
Resource Creation
        ↓
Microsoft.Resources.ResourceWriteSuccess
        ↓
Event Grid
        ↓
ResourceAttribution Function
        ↓
Extract Creator Identity
        ↓
Managed Identity
        ↓
Merge Attribution Tags
        ↓
CreatedBy
CreatedByType
CreatedAt
```

Event Grid subscription:

```text
evsub-finops-resource-attribution
```

Function:

```text
ResourceAttribution
```

Trigger:

```text
eventGridTrigger
```

---

## Least-Privilege Function Identity

The Azure Function uses its own system-assigned Managed Identity.

It does **not** receive `Contributor` or `Owner`.

Custom role:

```text
FinOps Resource Attribution Tagger
```

Allowed actions:

```text
Microsoft.Resources/tags/read
Microsoft.Resources/tags/write
```

That is the complete responsibility of the identity:

**read existing tags and merge attribution tags.**

---

## Attribution Preservation

The creator metadata represents the original resource creator.

Later resource changes must not overwrite that information.

Validated behavior:

```text
Initial resource:

CreatedBy = Claudia Native
CreatedAt = original timestamp

        ↓

Resource updated

        ↓

CreatedBy = Claudia Native
CreatedAt = original timestamp
```

Result:

```text
ORIGINAL ATTRIBUTION PRESERVED
```

---

# Final End-to-End Proof

The final proof combined the previous modules on one real VM.

```text
VM
vm-proof-e2e-final

Size:
Standard_B1s

Provisioning:
Succeeded
```

Final tags:

```text
AutoStop       = 0200

CostCenter     = FinOpsLab
Environment    = Lab
Owner          = Manuel
Project        = FinOpsGuardrails

CreatedBy      = Claudia Native
CreatedByType  = User
CreatedAt      = automatic creation timestamp
```

Network:

```text
Private IP = assigned
Public IP  = null
```

This single resource demonstrated:

```text
Group-Based RBAC
        +
Blast-Radius Control
        +
VM Size Policy
        +
Public IP Prevention
        +
AutoStop Requirement
        +
Governance Tag Inheritance
        +
Event Grid
        +
Azure Function
        +
Managed Identity
        +
Dynamic Creator Attribution
```

---

## Guardrail Platform State

At the end of validation, the platform contained the following policy assignments:

```text
allowed-vm-sizes
deny-public-ip
require-autostop-tag
audit-governance-tags

inherit-environment-tag
inherit-project-tag
inherit-costcenter-tag
inherit-owner-tag
```

Event-driven components:

```text
Event Grid:
evsub-finops-resource-attribution

Function:
ResourceAttribution

Trigger:
eventGridTrigger

Identity:
SystemAssigned

RBAC:
FinOps Resource Attribution Tagger
```

---

# Proof-Based Validation

Every module is validated using real Azure behavior instead of only showing configuration files.

Module 05 proof examples include:

- Entra ID group membership and RBAC boundaries
- platform-admin-created VNet
- engineer workload deployment
- automatic creator attribution
- no Public IP
- workload deletion allowed
- VNet deletion denied
- read-only user write denial
- multi-user attribution
- attribution preservation
- oversized VM Policy denial
- Event Grid integration
- deployed Function trigger
- Managed Identity
- minimum-permission custom role
- complete end-to-end governance state

The complete evidence set is stored under:

```text
modules/05-event-driven-resource-attribution/proofs/screenshots/
```

---

# Current Guardrails Evolution

```text
MODULE 01
Budget Alerts
      ↓
Detect unexpected cost


MODULE 02
AutoStop=0200
      ↓
Azure Automation
      ↓
Managed Identity
      ↓
Custom RBAC
      ↓
Control VM runtime cost


MODULE 03
Resource Group Governance Tags
      ↓
Azure Policy Modify
      ↓
Environment
Project
CostCenter
Owner


MODULE 04
Preventive Policy Baseline
      ↓
Approved VM sizes
No Public IP
AutoStop required
Governance audit
      ↓
Stop risky resources before deployment


MODULE 05
Entra ID + RBAC
      ↓
Resource Creation
      ↓
ResourceWriteSuccess
      ↓
Event Grid
      ↓
Azure Function
      ↓
Managed Identity
      ↓
CreatedBy / CreatedByType / CreatedAt
      ↓
Dynamic accountability


MODULE 06
Terraform
      ↓
Desired State
      ↓
Reproducible Guardrail Platform
```

---

# The Drift Lesson

During final Module 05 validation, an important problem appeared.

The tag-governance implementation from Module 03 already existed in the repository.

The Resource Group still contained the expected central tags.

But the actual Azure environment no longer contained the corresponding inheritance policy assignments.

The intended configuration and the deployed configuration had drifted apart.

The missing assignments were:

```text
inherit-environment-tag
inherit-project-tag
inherit-costcenter-tag
inherit-owner-tag
```

After redeploying Module 03, the final E2E workload again received:

```text
Environment
Project
CostCenter
Owner
```

This became an important engineering lesson:

```text
Documentation
        +
Deployment Scripts
        !=
Guaranteed Current State
```

A deployment script can recreate infrastructure.

It does not continuously prove that the deployed environment still matches the intended architecture.

That problem creates the next logical step for this project.

---

# 06 — Terraform Guardrail Platform 🔜

Module 06 will move the individual guardrails toward a Terraform-managed desired state.

Target architecture:

```text
Terraform
    |
    +--> Budget Guardrails
    |
    +--> Automation
    |
    +--> RBAC
    |
    +--> Custom Roles
    |
    +--> Tag Governance
    |
    +--> Azure Policy
    |
    +--> Event Grid
    |
    +--> Azure Function Infrastructure
    |
    +--> Managed Identity
    |
    v
Reproducible Governance Platform
```

The goal is not simply to rewrite CLI commands in Terraform.

The goal is to solve the operational problem exposed during Module 05:

> How do I know that the Azure environment still matches the architecture I intended to deploy?

Terraform will provide the desired-state layer needed to make drift visible and the platform reproducible.

---

# Module Overview

| Module | Topic | Status |
|---|---|---|
| 01 | Budget Alerts + Action Group | ✅ Completed |
| 02 | Nightly VM AutoStop + Managed Identity | ✅ Completed |
| 03 | Governance Tag Inheritance | ✅ Completed |
| 04 | Preventive Azure Policy Baseline | ✅ Completed |
| 05 | Event-Driven Resource Attribution | ✅ Completed |
| 06 | Terraform Guardrail Platform | 🔜 Next |

---

# Guardrail Layers

```text
COST VISIBILITY
      ↓
Budget Alerts

OPERATIONAL CONTROL
      ↓
Automation Runbooks

IDENTITY
      ↓
Microsoft Entra ID

AUTHORIZATION
      ↓
Group-Based RBAC

LEAST PRIVILEGE
      ↓
Custom Roles

GOVERNANCE CONTEXT
      ↓
Tag Inheritance

PREVENTION
      ↓
Azure Policy

EVENT REACTION
      ↓
Event Grid

AUTOMATION
      ↓
Azure Functions

ACCOUNTABILITY
      ↓
CreatedBy Attribution

DESIRED STATE
      ↓
Terraform
```

---

# Design Principles

- CLI-first learning and validation
- Evidence-first documentation
- Least privilege
- Group-based authorization
- Scoped blast radius
- Separation of platform and workload responsibilities
- Prevent before reacting
- Automatic governance where possible
- No unnecessary Public IP exposure
- Managed Identity instead of stored credentials
- Real end-to-end proof scenarios
- Cleanup after validation
- Infrastructure evolving toward desired-state management

---

# Repository Structure

```text
modules/
│
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
├── 05-event-driven-resource-attribution/
│   ├── function/
│   ├── infra/
│   ├── proofs/
│   │   └── screenshots/
│   └── README.md
│
└── 06-terraform-guardrail-platform/
    ├── modules/
    ├── environments/
    └── README.md
```

---

# Why This Matters

Cloud governance is not only about detecting mistakes.

A cloud resource should be able to answer:

```text
What environment does this belong to?

Which project is responsible?

Which cost center pays for it?

Who owns it?

Who actually created it?

Which identity may manage it?

Which automation may act on it?

Does it need to run right now?

Should this resource have been allowed to exist?

Can the environment be reproduced if something disappears?
```

The repository builds those answers one guardrail at a time.

---

## Current Status

```text
✅ Module 01 — Budget Alerts
✅ Module 02 — Nightly VM AutoStop
✅ Module 03 — Tag Governance
✅ Module 04 — Preventive Policy Baseline
✅ Module 05 — Event-Driven Resource Attribution

🔜 Module 06 — Terraform Guardrail Platform
```

> Started as cost automation.  
> Evolved into governance.  
> Now moving toward a reproducible Azure guardrail platform.