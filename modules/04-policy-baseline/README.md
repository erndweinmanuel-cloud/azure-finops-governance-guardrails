# Module 04 — Policy Baseline

Preventive Azure Policy guardrails for the shared FinOps lab environment.

This module is part of the **FinOps Guardrails Evolution** project. Module 04 owns the custom policy definitions and policy assignments described below. It does **not** own the shared Resource Group or its Foundation tags.

## Evolution Context

The previous modules focused on visibility, automation, and accountability:

- **Module 01:** Budget Alerts — detect cost thresholds early
- **Module 02:** Nightly VM Auto-Stop — automatically stop tagged VMs with least privilege
- **Module 03:** Tag Governance Policy — inherit governance tags from the Resource Group
- **Module 04:** Policy Baseline — prevent risky or expensive resources and audit governance metadata

The key idea of this module:

> Do not only react when costs already exist. Prevent unnecessary cost risks before resources are created.

## Ownership Boundary

### Shared Foundation — not owned by Module 04

Module 04 consumes but does not create, update, or delete:

- `rg-finops-lab`
- Foundation governance tag values on `rg-finops-lab`
- shared networking such as `vnet-finops-lab`
- Module 03 tag-inheritance assignments
- unrelated resources in the shared lab scope

The required Foundation governance tags are:

```text
Environment
Project
CostCenter
Owner
```

The deployment script validates that the shared Resource Group exists and that these tags have values.

### Module 04 — owned resources

Module 04 owns four subscription-level custom policy definitions:

```text
finops-allowed-vm-sizes
finops-deny-public-ip
finops-require-vm-autostop
finops-audit-governance-tags
```

and four assignments on `rg-finops-lab`:

```text
allowed-vm-sizes
deny-public-ip
require-autostop-tag
audit-governance-tags
```

The cleanup script removes only these Module 04 assignments and definitions. It preserves the shared Foundation and unrelated policy assignments.

## Guardrails

| Guardrail | Assignment | Effect | Purpose |
|---|---|---:|---|
| Allow only approved VM sizes | `allowed-vm-sizes` | Deny | Prevent oversized or expensive VMs in the lab |
| Deny public IP addresses | `deny-public-ip` | Deny | Avoid unnecessary public exposure |
| Require AutoStop tag on lab VMs | `require-autostop-tag` | Deny | Ensure new VMs meet the AutoStop contract |
| Audit missing governance tags | `audit-governance-tags` | Audit | Detect resources without required cost and ownership metadata |

## Allowed VM Sizes

Only these VM sizes are allowed:

```text
Standard_B1s
Standard_B2s
```

Everything else is denied by policy.

## AutoStop Requirement

VMs must carry:

```text
AutoStop=0200
```

Module 02 consumes the same operational tag when selecting VMs for scheduled deallocation.

## Governance Tag Audit

The audit policy checks for:

```text
Environment
Project
CostCenter
Owner
```

The effect is `Audit`, so the policy records drift without blocking deployment.

Module 03 and Module 04 intentionally have different responsibilities:

- Module 03 inherits missing governance tags for supported new resources.
- Module 04 reports resources that are still missing one or more required governance tags.

Existing Brownfield resources can therefore remain non-compliant until they are explicitly remediated.

## Brownfield Hardening

The original Module 04 deployment mixed module ownership with shared Foundation ownership. It created or updated `rg-finops-lab` and wrote the central Resource Group tags.

The hardened deployment no longer does that.

Current deployment behavior:

1. Validate the active Azure subscription.
2. Validate that `rg-finops-lab` already exists.
3. Validate that the four required Foundation tag values exist.
4. Validate each existing custom policy definition semantically against the JSON source in `infra/`.
5. Create a custom policy definition only when it is missing.
6. Validate each existing assignment for display name, definition ID, enforcement mode, parameters, and scope.
7. Create an assignment only when it is missing.
8. Fail on unexpected drift instead of silently overwriting a healthy or changed live configuration.

This makes configuration drift visible before Terraform import.

### Git Bash / MSYS handling

Azure resource IDs beginning with `/subscriptions/...` can be rewritten by Git Bash/MSYS into Windows paths.

The hardened script avoids this in two ways:

- Azure CLI calls that use Azure resource IDs run with `MSYS_NO_PATHCONV=1`.
- Python semantic validation receives primitive values such as subscription ID and resource names and constructs Azure resource IDs internally.

This prevents false drift such as:

```text
C:/Program Files/Git/subscriptions/...
```

being compared with the real Azure resource ID:

```text
/subscriptions/...
```

## Deployment

From PowerShell:

```powershell
& "C:\Program Files\Git\bin\bash.exe" modules/04-policy-baseline/scripts/deploy.sh
```

Syntax check:

```powershell
& "C:\Program Files\Git\bin\bash.exe" -n modules/04-policy-baseline/scripts/deploy.sh
& "C:\Program Files\Git\bin\bash.exe" -n modules/04-policy-baseline/scripts/cleanup.sh
```

Do not run `cleanup.sh` as part of normal validation. It exists to define the ownership boundary and deliberately removes Module 04 resources.

## Brownfield Validation — 2026-10-04

### Deployment validation

The hardened deployment was run against the existing Azure environment.

Results:

- shared Resource Group found
- Foundation governance tags validated
- all four custom definitions already existed
- all four custom definitions matched the repository definitions
- all four assignments already existed
- all four assignments matched the expected definition, scope, enforcement mode, and parameters
- no functional Module 04 configuration drift was found
- shared Foundation resources were preserved

## End-to-End Validation — 2026-10-04

### Deny public IP

Test resource:

```text
pip-m04-deny-test
```

Expected result:

```text
RequestDisallowedByPolicy
```

Observed policy:

```text
deny-public-ip
finops-deny-public-ip
```

A follow-up lookup returned:

```text
ResourceNotFound
```

No Public IP was created.

### Require AutoStop tag

Test VM:

```text
vm-m04-autostop-deny
```

The VM used an allowed size and no Public IP, but intentionally omitted `AutoStop=0200`.

Azure Policy denied the deployment with:

```text
RequestDisallowedByPolicy
```

Observed policy:

```text
require-autostop-tag
finops-require-vm-autostop
```

The evaluation showed that `tags[AutoStop]` did not exist.

Follow-up checks confirmed:

```text
VM   -> ResourceNotFound
NIC  -> not present
Disk -> not present
```

### Deny unapproved VM size

Test VM:

```text
vm-m04-size-deny
```

The deployment included the required AutoStop tag but intentionally used:

```text
Standard_D2s_v5
```

Azure Policy denied the deployment with:

```text
RequestDisallowedByPolicy
```

The evaluation compared:

```text
expressionValue: Standard_D2s_v5
targetValue:
  - Standard_B1s
  - Standard_B2s
operator: NotIn
```

Observed policy:

```text
allowed-vm-sizes
finops-allowed-vm-sizes
```

Follow-up checks confirmed that no VM, NIC, or disk remained.

### Audit governance tags

An on-demand Policy compliance scan was triggered for `rg-finops-lab`.

The current audit result showed one compliant resource and seven non-compliant existing resources.

The non-compliant Brownfield resources include:

```text
stfinopsfunc94976
ASP-rgfinopslab-bcdf
func-finops-attribution-92096
Application Insights component
Application Insights Smart Detection
Event Grid system topic
vnet-finops-lab
```

The resources are missing one or more of:

```text
Environment
Project
CostCenter
Owner
```

This is a real Brownfield finding, not a Module 04 failure. Module 04 is correctly reporting historical tag drift.

The existing Network Security Group:

```text
vm-finops-autostop-01NSG
```

was compliant with the governance tags but appears to be a leftover from the earlier Module 02 proof VM. Its attachment/usage should be verified before deletion.

## Proof Artifacts

Historical proof artifacts remain under:

```text
proofs/cli/
proofs/screenshots/
```

They include earlier validation of:

- Resource Group governance tags
- custom policy definitions
- policy assignments
- allowed B1s VM deployment
- missing AutoStop denial
- oversized VM denial
- Public IP denial

The 2026-10-04 Brownfield revalidation adds the current ownership, semantic drift, and live compliance findings documented above.

## Terraform Direction

Current classification:

| Resource | Owner | Direction |
|---|---|---|
| `rg-finops-lab` | Foundation | IMPORT |
| Foundation governance tags | Foundation | IMPORT / manage centrally |
| `vnet-finops-lab` | Foundation / Networking | IMPORT |
| four Module 04 custom policy definitions | Module 04 | IMPORT |
| four Module 04 policy assignments | Module 04 | IMPORT |
| E2E test resources | Temporary | TEMPORARY |

Terraform work starts only after Modules 01–05 and the shared Foundation ownership have been stabilized.

## Key Learnings

- Azure Policy can enforce preventive FinOps controls before resources incur cost.
- Brownfield migration requires validating the live policy rule and parameters, not only checking that an object with the expected name exists.
- Shared Resource Groups and central tags need a single clear Foundation owner.
- A deploy script should not silently overwrite unexpected Brownfield drift.
- Deny tests must verify that rejected resources were not partially created.
- Audit findings are useful evidence of historical drift and should not automatically be remediated by the auditing module.
- Git Bash/MSYS path conversion can corrupt Azure resource IDs passed to subprocesses and must be handled explicitly.

## Result

Module 04 now has a clear ownership boundary, drift-aware deployment behavior, ownership-safe cleanup behavior, and current end-to-end proof for all four guardrails.
