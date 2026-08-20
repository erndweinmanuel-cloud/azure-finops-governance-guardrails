# Module 05 - Event-Driven Resource Attribution

## Status

In Progress

Current implementation:

- Identity and RBAC foundation completed
- Azure Activity Log event schema validated
- Azure Function foundation implemented
- Event Grid trigger validated locally
- Creator identity extraction validated locally
- Azure deployment and automatic resource tagging pending

---

## Goal

Automatically attribute newly created Azure resources to the identity that created them.

Target resource tags:

- `CreatedBy`
- `CreatedByType`

The attribution pipeline will use Azure Activity Log events, Event Grid, and an Azure Function.

---

## Architecture

```text
Entra ID Identity
        |
        v
Group-based Azure RBAC
        |
        v
Azure Policy Guardrails
        |
        v
Resource Creation
        |
        v
Activity Log / ResourceWriteSuccess
        |
        v
Event Grid
        |
        v
Azure Function
        |
        v
CreatedBy / CreatedByType tags
```

The module extends the preventive governance controls from the previous modules with dynamic resource attribution.

Azure Policy determines whether a deployment is allowed.

Azure RBAC determines who is allowed to perform the deployment.

Event-driven attribution determines who actually created the resource.

---

## Identity Model

Access to the lab environment is assigned through Microsoft Entra ID security groups rather than directly to individual users.

### Engineers

Security group:

`grp-azure-finops-lab-engineers`

The engineers group receives the custom Azure RBAC role:

`FinOps Lab VM Engineer`

Engineers can deploy and manage approved VM workload resources without receiving broad `Contributor` access.

### Auditors

Security group:

`grp-azure-finops-lab-auditors`

The auditors group receives the built-in Azure `Reader` role on the lab resource group.

Auditors can inspect resources but cannot create, modify, or delete workload resources.

---

## Group-Based RBAC Model

```text
Engineer Identity
        |
        v
grp-azure-finops-lab-engineers
        |
        v
FinOps Lab VM Engineer
        |
        v
rg-finops-lab


Auditor Identity
        |
        v
grp-azure-finops-lab-auditors
        |
        v
Reader
        |
        v
rg-finops-lab
```

RBAC assignments are attached to groups rather than individual users.

This makes access management easier to scale and avoids maintaining separate Azure role assignments for every engineer.

---

## Separation of Duties

Platform infrastructure and workload infrastructure are deliberately separated.

### Platform / Admin Responsibilities

The platform administrator controls:

- Virtual Networks
- Subnets
- Azure RBAC
- Custom Role Definitions
- Azure Policy
- Governance infrastructure
- Shared platform components

### Engineer Responsibilities

Engineers can:

- Deploy permitted virtual machines
- Read virtual machines
- Start virtual machines
- Restart virtual machines
- Deallocate virtual machines
- Delete permitted virtual machines
- Create and manage managed disks
- Create and manage network interfaces
- Attach network interfaces to virtual machines
- Read existing VNets
- Read existing subnets
- Join existing subnets

Engineers cannot manage the lifecycle of the underlying platform VNet.

The VNet and subnet are provided by the platform layer and consumed by workload engineers.

This reduces the blast radius of workload identities.

---

## Custom RBAC Role

Role definition:

`infra/finops-lab-vm-engineer.role.json`

Role name:

`FinOps Lab VM Engineer`

The role was developed using an iterative least-privilege approach.

Instead of assigning the built-in `Contributor` role, only permissions required by the actual VM deployment workflow were added.

The deployment workflow was repeatedly tested using an engineer identity.

When Azure returned an authorization failure, the missing permission was evaluated and added only when required by the intended workload.

Examples of required permissions discovered during validation include:

```text
Microsoft.Resources/deployments/write
Microsoft.Resources/deployments/read
Microsoft.Resources/deployments/operationstatuses/read

Microsoft.Network/networkInterfaces/join/action
Microsoft.Network/virtualNetworks/subnets/join/action
```

This produces a significantly smaller permission surface than assigning `Contributor`.

---

## Platform Networking Model

The validation environment used a platform-managed network:

```text
vnet-finops-lab
10.20.0.0/16
        |
        +-- subnet-workload
            10.20.1.0/24
```

The VNet and subnet were created by the platform administrator.

Engineers were allowed to consume the existing subnet but were not granted VNet lifecycle permissions.

This was validated by attempting to delete the VNet using an engineer identity.

The operation was denied because the engineer role does not contain:

```text
Microsoft.Network/virtualNetworks/delete
```

This confirms the intended separation between platform administration and workload deployment.

---

## RBAC Validation

The Identity and Authorization foundation has been functionally validated.

### Auditor Validation

Validated behavior:

- Authentication successful
- Subscription visible
- Resource group readable
- Resource creation denied

A storage account creation attempt was rejected with:

```text
AuthorizationFailed
Microsoft.Storage/storageAccounts/write
```

This confirmed that the auditor identity has read-only access.

### Engineer Validation

Validated behavior:

- Passwordless authentication successful
- Resource group readable
- Existing VNet readable
- NIC creation successful
- Existing subnet join successful
- ARM deployment successful
- VM creation successful
- VM deallocation successful
- Platform VNet deletion denied

The final VM deployment used:

```text
VM size:      Standard_B1s
Public IP:    None
AutoStop tag: 0200
```

The VM was successfully deployed using the custom role without assigning `Contributor`.

---

## Least-Privilege Validation Process

The custom role was intentionally started with a restricted permission set.

The validation process followed this pattern:

```text
Restricted Custom Role
        |
        v
Deployment Attempt
        |
        v
Authorization Failure
        |
        v
Identify Required Action
        |
        v
Add Only Required Permission
        |
        v
Retry Deployment
```

Example:

```text
VM Deployment
        |
        v
AuthorizationFailed
Microsoft.Resources/deployments/write
        |
        v
Deployment permissions added
        |
        v
Retry
        |
        v
LinkedAuthorizationFailed
Microsoft.Network/networkInterfaces/join/action
        |
        v
NIC join permission added
        |
        v
Retry
        |
        v
SUCCESS
```

This demonstrates that the custom role was derived from the actual workload requirements instead of starting with excessive privileges.

---

## Governance Layers

Module 05 now builds on several independent control layers:

```text
Entra ID
Identity
        |
        v
Azure RBAC
Who may perform an action?
        |
        v
Azure Policy
Is the requested resource allowed?
        |
        v
Activity Log
What happened and who initiated it?
        |
        v
Event Grid
React to successful resource creation
        |
        v
Azure Function
Determine creator identity
        |
        v
Resource Tags
CreatedBy / CreatedByType
```

This creates multiple independent governance controls instead of relying on a single security mechanism.

---

## Current Implementation Status

Completed:

- Entra ID test identities
- Passwordless authentication
- Engineer security group
- Auditor security group
- Group-based Azure RBAC
- Custom least-privilege VM Engineer role
- Auditor read-only validation
- Engineer VM deployment validation
- Platform / workload separation validation
- Azure Activity Log inspection using a real resource creation event
- `ResourceWriteSuccess` event validation
- Caller and identity claims validation
- Azure Functions Core Tools local environment
- Local Azurite development storage
- Python Azure Function foundation
- Event Grid trigger implementation
- Local Event Grid trigger validation
- Resource ID extraction
- Operation extraction
- Creator identity extraction
- Identity type extraction
- Creation timestamp extraction
- Structured attribution logging
- Cleanup of temporary Azure validation resources

Pending:

- Resource tagging implementation
- Local tagging logic validation
- Azure Function infrastructure deployment
- Managed Identity for the Azure Function
- Least-privilege RBAC for resource tagging
- Azure Function deployment
- Event Grid subscription in Azure
- Real Azure Event Grid integration
- `CreatedBy` tagging
- `CreatedByType` tagging
- `CreatedAt` tagging
- End-to-end validation with real Azure resource creation
- Edge-case validation
- Final CLI proofs
- Final screenshots

---

## Next Step

Implement the event-driven attribution pipeline:

```text
Resource Creation
        |
        v
Activity Log
        |
        v
ResourceWriteSuccess
        |
        v
Event Grid
        |
        v
Azure Function
        |
        +--> Extract caller identity
        |
        +--> Determine identity type
        |
        v
Update Resource Tags
        |
        +--> CreatedBy
        +--> CreatedByType
```

The Azure Activity Log event schema and caller identity claims have been validated.

A local Python Azure Function now successfully receives simulated `Microsoft.Resources.ResourceWriteSuccess` events through an Event Grid trigger and extracts:

- Resource ID
- Operation
- Creator identity
- Creator identity type
- Creation timestamp

The next implementation step is to add the resource tagging engine and validate the tagging logic locally before deploying the Function to Azure.

After local validation, the Function will be deployed with a Managed Identity and least-privilege RBAC permissions. Azure Event Grid will then connect real resource creation events to the Function.

Final proofs will be collected after the complete event-driven attribution pipeline is operational.
