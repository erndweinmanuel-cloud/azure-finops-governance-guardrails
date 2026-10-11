# Brownfield Findings - 2026-09-05

## Goal

Validate the current Azure state before migrating the FinOps governance platform to Terraform.

## Findings

### Module 02 drift

The following Module 02 resources still exist:

- Automation Account `aa-ops-guardrails`
- Runbook `rb-stop-tagged-vms`
- Schedule `sched-stop-vms-0200`
- Runbook-to-Schedule link

The following required resources were missing during the initial Brownfield inspection:

- Custom Role `FinOps VM AutoStop Operator`
- Role Assignment for the Automation Account Managed Identity on `rg-finops-lab`

The AutoStop runbook therefore no longer had the required permissions.

Module 02 was subsequently repaired and validated end-to-end.

### False-positive Automation job

The initial Automation job reported `Completed`, although the job stream contained:

```text
Connected. Subscription:
'this.Client.SubscriptionId' cannot be null.
Found 0 VM(s) in rg-finops-lab with tag AutoStop=0200
```

This showed that job status alone was not sufficient to validate the guardrail. The runbook was hardened to fail explicitly when authentication, subscription context, resource discovery, or VM deallocation fails.

### Root cause

Azure Activity Log showed that `rg-finops-lab` was completely deleted on 2026-07-18.

During deletion, Module 02 RBAC assignments and other Resource-Group-scoped assignments were removed.

The Resource Group was later recreated for subsequent modules, but not all previous dependencies were restored.

### Architecture finding

`rg-finops-lab` originally belonged to the Module 02 test environment.

The platform later evolved and Modules 02-05 now depend on the same Resource Group.

Therefore:

- `rg-finops-lab` must be treated as a shared Foundation resource.
- Module 02 consumes the Resource Group but must not own or delete it.
- Individual module cleanup scripts must remove only resources owned by that module.

The same ownership principle also applies to `rg-ops-guardrails`.

### Module numbering is not the dependency graph

The module numbers describe the order in which the project evolved, not the real technical dependency order.

The target structure is closer to:

```text
FOUNDATION
├── rg-ops-guardrails
├── rg-finops-lab
│   ├── Governance Tags
│   └── Platform Networking
│
├── Module 01 - Budget Alerts
├── Module 02 - VM AutoStop
├── Module 03 - Tag Governance
├── Module 04 - Policy Baseline
└── Module 05 - Event-Driven Attribution
```

Shared Foundation resources must have a single clear owner.

## Module 03 validation

Module 03 live state was healthy during Brownfield inspection:

- all four tag-inheritance assignments existed
- all assignments referenced the expected built-in inheritance policy
- all four SystemAssigned identities existed
- each identity had `Tag Contributor` at the exact `rg-finops-lab` scope

The repository implementation was hardened so that Module 03 no longer owns the shared Resource Group or its tag values.

A temporary storage-account test confirmed that new resources can receive:

```text
Environment=Lab
Project=FinOpsGuardrails
CostCenter=FinOpsLab
Owner=Manuel
```

## Module 04 validation - 2026-10-04

### Live policy state

All four Module 04 custom policy definitions exist and match the repository definitions for their important semantics:

```text
finops-allowed-vm-sizes
finops-deny-public-ip
finops-require-vm-autostop
finops-audit-governance-tags
```

All four assignments exist at `rg-finops-lab`:

```text
allowed-vm-sizes
deny-public-ip
require-autostop-tag
audit-governance-tags
```

Expected assignment parameters were confirmed:

```text
allowed VM sizes: Standard_B1s, Standard_B2s
VM size effect: Deny
Public IP effect: Deny
AutoStop tag: AutoStop=0200
AutoStop effect: Deny
Governance tag effect: Audit
EnforcementMode: Default
```

No functional Module 04 configuration drift was found.

### Ownership drift in repository implementation

The original Module 04 deployment still created or updated the shared Resource Group and central governance tags.

That behavior violated the Foundation ownership boundary.

The hardened Module 04 deployment now:

- validates `rg-finops-lab` instead of creating it
- validates Foundation governance tags instead of writing them
- validates existing custom policy definitions semantically
- creates definitions only when missing
- validates assignment scope, definition, parameters, display name, and enforcement mode
- creates assignments only when missing
- fails on unexpected drift instead of silently overwriting it

The cleanup script removes only Module 04 assignments and custom definitions and preserves the shared Foundation and unrelated assignments.

### Git Bash / MSYS path-conversion issue

During hardening, the semantic assignment check initially reported false drift because Git Bash/MSYS rewrote Azure resource IDs passed to Python:

```text
/subscriptions/...
```

became:

```text
C:/Program Files/Git/subscriptions/...
```

The script was corrected so Python receives primitive values such as subscription ID and names and constructs Azure resource IDs internally.

The corrected hardened deployment subsequently validated all definitions and assignments successfully.

### Module 04 E2E results

#### Public IP deny

Creating:

```text
pip-m04-deny-test
```

was blocked with:

```text
RequestDisallowedByPolicy
```

by:

```text
deny-public-ip
finops-deny-public-ip
```

A follow-up lookup returned `ResourceNotFound`.

#### AutoStop requirement

Creating:

```text
vm-m04-autostop-deny
```

without `AutoStop=0200` was blocked with `RequestDisallowedByPolicy`.

Azure Policy identified:

```text
require-autostop-tag
finops-require-vm-autostop
```

and evaluated the missing `tags[AutoStop]`.

No VM, NIC, or disk remained.

#### Allowed VM sizes

Creating:

```text
vm-m04-size-deny
```

with `Standard_D2s_v5` and a valid AutoStop tag was blocked by:

```text
allowed-vm-sizes
finops-allowed-vm-sizes
```

The policy evaluation compared `Standard_D2s_v5` against:

```text
Standard_B1s
Standard_B2s
```

with operator `NotIn`.

No VM, NIC, or disk remained.

#### Governance tag audit

A fresh Resource-Group policy scan returned one compliant and seven non-compliant resources for `audit-governance-tags`.

The current non-compliant Brownfield resources are:

- `stfinopsfunc94976`
- `ASP-rgfinopslab-bcdf`
- `func-finops-attribution-92096` Function App
- `func-finops-attribution-92096` Application Insights component
- `Application Insights Smart Detection`
- Event Grid system topic `rg-finops-lab-30892968-5599-4372-bc1a-2229e2d9b3aa`
- `vnet-finops-lab`

The Storage Account, App Service Plan, Function App, Application Insights component, and Smart Detection Action Group currently have no governance tags.

The Event Grid system topic and VNet contain attribution tags such as `CreatedAt`, `CreatedBy`, and `CreatedByType`, but are missing one or more required governance tags:

```text
Environment
Project
CostCenter
Owner
```

This is historical tag drift. Module 04 is correctly detecting it.

Do not remediate these resources from Module 04. Their ownership must be handled by Module 05 or the shared Foundation.

### Orphan candidate from Module 02 proof

The current inventory also contains:

```text
vm-finops-autostop-01NSG
```

The NSG has the expected governance and attribution tags, but the proof VM itself was deleted after the Module 02 E2E test.

Before deleting the NSG, verify that it is not attached to any NIC or subnet.

## Module 05 validation - 2026-10-04

### Live state

The Module 05 event-driven attribution platform was inspected before repository hardening.

Confirmed healthy:

- Function App `func-finops-attribution-92096`
- Flex Consumption plan `ASP-rgfinopslab-bcdf`
- Storage Account `stfinopsfunc94976`
- Application Insights
- Event Grid system topic for `rg-finops-lab`
- Event subscription `evsub-finops-resource-attribution`
- Function system-assigned Managed Identity
- custom role `FinOps Resource Attribution Tagger`
- exact Function MI role assignment at `rg-finops-lab`
- custom role `FinOps Lab VM Engineer`
- engineer-group role assignment at `rg-finops-lab`
- auditor-group `Reader` assignment at `rg-finops-lab`

The Function runtime is Python 3.14 on Flex Consumption. The Event Grid subscription is provisioned successfully, listens for `Microsoft.Resources.ResourceWriteSuccess`, and targets `func-finops-attribution-92096/functions/ResourceAttribution`.

### Identity and RBAC

Current group-based assignments:

```text
grp-azure-finops-lab-engineers
    -> FinOps Lab VM Engineer
    -> rg-finops-lab

grp-azure-finops-lab-auditors
    -> Reader
    -> rg-finops-lab
```

The Function Managed Identity has `FinOps Resource Attribution Tagger` at the exact `rg-finops-lab` scope. The custom tagger role contains only:

```text
Microsoft.Resources/tags/read
Microsoft.Resources/tags/write
```

### Module 05 E2E

A temporary Storage Account received the Module 03 governance tags. A fresh resource write then triggered the Module 05 attribution pipeline and produced:

```text
CreatedBy     = manuel.erndwein.cloud@outlook.com
CreatedByType = User
CreatedAt     = 2026-10-04 14:41:30.384716+00:00
```

A subsequent resource update confirmed that `CreatedBy` and `CreatedAt` remained unchanged. The temporary Storage Account was deleted after validation and `ResourceNotFound` confirmed cleanup.

Module 05 is therefore functionally E2E healthy.

### Validation-induced storage credential incident

During validation, Storage Account keys were rotated. `AzureWebJobsStorage` was initially updated while `DEPLOYMENT_STORAGE_CONNECTION_STRING` still referenced the rotated key.

Event Grid then showed matched events with delivery failures and the Function did not execute for the affected event. After repairing the deployment-storage connection and restarting the Function, a fresh resource write completed successfully.

This incident was introduced during validation and is not classified as pre-existing Brownfield drift.

### Repository reproducibility gap

The live Module 05 implementation is healthy, but `modules/05-event-driven-resource-attribution/scripts/` is currently empty.

The repository therefore cannot yet reproducibly reconcile or clean up the complete Module 05 infrastructure. This must be hardened before Shared Foundation stabilization and Terraform migration.

### Ownership direction

Shared Foundation owns:

- `rg-finops-lab`
- central governance tag values
- `vnet-finops-lab`
- `subnet-workload`

External identity objects:

- `grp-azure-finops-lab-engineers`
- `grp-azure-finops-lab-auditors`

Module 05 owns or manages:

- Function infrastructure
- Function Storage Account
- Flex Consumption hosting plan
- Application Insights
- Event Grid system topic
- Event Grid event subscription
- custom Module 05 role definitions
- Module 05 role assignments

The Function Managed Identity follows the Function App lifecycle. Service-generated Application Insights resources must not be blindly deleted as independently owned resources.

## Live inventory

### rg-ops-guardrails

- `aa-ops-guardrails`
- `aa-ops-guardrails/rb-stop-tagged-vms`
- `ag-budget-alerts`

### rg-finops-lab

- `stfinopsfunc94976`
- `ASP-rgfinopslab-bcdf`
- `func-finops-attribution-92096`
- Application Insights component for the Function
- `Application Insights Smart Detection` Action Group
- Event Grid system topic for `rg-finops-lab`
- `vnet-finops-lab`
- `vm-finops-autostop-01NSG` — orphan candidate, verify before deletion

## Ownership direction

| Resource / Area | Target Owner | Terraform Direction |
|---|---|---|
| `rg-ops-guardrails` | Foundation | IMPORT |
| `rg-finops-lab` | Foundation | IMPORT |
| Foundation governance tags | Foundation | IMPORT / manage centrally |
| `vnet-finops-lab` | Foundation / Networking | IMPORT |
| `ag-budget-alerts` | Module 01 | IMPORT |
| `aa-ops-guardrails` | Module 02 | IMPORT |
| `rb-stop-tagged-vms` | Module 02 | IMPORT |
| AutoStop Custom Role | Module 02 | IMPORT |
| AutoStop Role Assignment | Module 02 | IMPORT |
| Proof VM | Temporary E2E | TEMPORARY |
| `vm-finops-autostop-01NSG` | Module 02 proof artifact candidate | VERIFY / likely REMOVE |
| Tag inheritance policies | Module 03 | IMPORT |
| Module 04 custom policy definitions | Module 04 | IMPORT |
| Module 04 policy assignments | Module 04 | IMPORT |
| Function infrastructure | Module 05 | IMPORT / validate |
| Event Grid attribution resources | Module 05 | IMPORT / validate |

## Brownfield strategy

Before Terraform migration:

1. Identify resource ownership.
2. Map dependencies and dependents.
3. Repair configuration drift.
4. Validate cleanup boundaries.
5. Ensure each module removes only its own resources.
6. Validate modules end-to-end.
7. Classify resources as `IMPORT`, `RECREATE`, `EXTERNAL` or `TEMPORARY`.
8. Migrate the stable platform to Terraform.
9. Run `terraform plan` and confirm there are no unexpected changes.
10. Perform an end-to-end validation of the Terraform-managed platform.

## Current status

```text
Module 01  validated
Module 02  repaired and E2E validated
Module 03  ownership-hardened and E2E validated
Module 04  ownership-hardened and E2E validated
Module 05  live/E2E validated; repository hardening in progress
Foundation extraction  after Module 05 repository hardening
Terraform migration    after Foundation stabilization
```

## Next step

Harden the Module 05 repository implementation:

1. create a deployment script that validates shared Foundation and external identity dependencies
2. reconcile only Module 05-owned resources
3. create a cleanup script with strict ownership boundaries
4. validate both scripts without dismantling the healthy live platform
5. update Module 05 documentation
6. commit the hardened Module 05 implementation
7. stabilize the shared Foundation
8. only then begin Terraform Brownfield migration
