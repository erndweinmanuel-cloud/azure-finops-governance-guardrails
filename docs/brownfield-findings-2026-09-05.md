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

The following required resources are missing:

- Custom Role `FinOps VM AutoStop Operator`
- Role Assignment for the Automation Account Managed Identity on `rg-finops-lab`

The AutoStop runbook therefore no longer has the required permissions.

### False-positive Automation job

The latest Automation job reported `Completed`, although the job stream contained:

```text
Connected. Subscription:
'this.Client.SubscriptionId' cannot be null.
Found 0 VM(s) in rg-finops-lab with tag AutoStop=0200
```

This means job status alone is not sufficient to validate the guardrail. The runbook must fail explicitly when authentication, subscription context, resource discovery or VM deallocation fails.

### Root cause

Azure Activity Log showed that `rg-finops-lab` was completely deleted on 2026-07-18.

During deletion, the Module 02 RBAC assignment and other resource-group-scoped assignments were removed.

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

## Ownership direction

| Resource / Area | Target Owner | Terraform Direction |
|---|---|---|
| `rg-ops-guardrails` | Foundation | IMPORT |
| `rg-finops-lab` | Foundation | IMPORT |
| `vnet-finops-lab` | Foundation / Networking | IMPORT |
| `ag-budget-alerts` | Module 01 | IMPORT |
| `aa-ops-guardrails` | Module 02 | IMPORT |
| `rb-stop-tagged-vms` | Module 02 | IMPORT |
| AutoStop Custom Role | Module 02 | RECREATE |
| AutoStop Role Assignment | Module 02 | RECREATE |
| Proof VM | Temporary E2E | TEMPORARY |
| Tag inheritance policies | Module 03 | IMPORT / validate |
| Preventive policy baseline | Module 04 | IMPORT / validate |
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

## Next step

Start with Module 02:

1. Update `cleanup.sh` so it never deletes `rg-finops-lab`.
2. Restore the missing AutoStop custom role and RBAC assignment.
3. Make the runbook fail fast on Azure errors.
4. Validate dependencies after deployment.
5. Run an end-to-end AutoStop test.
6. Commit the repaired module before starting Terraform import work.
