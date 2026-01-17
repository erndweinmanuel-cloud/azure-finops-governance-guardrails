# Module 02 — Nightly VM Auto-Stop (Tag-Based Guardrail)

This module automatically **deallocates** Azure VMs based on a tag.
Goal: a practical FinOps/Governance guardrail with clean, reproducible proof artifacts.

## What it does
- Finds VMs with tag **`AutoStop=0200`**
- Reads the VM power state reliably via **PowerState CODE**
- Deallocates VMs that are currently running

Why this matters:
- `DisplayStatus` can be `"VM running"`
- `Code` is `"PowerState/running"`
If you compare the wrong one, your runbook will incorrectly **skip** a running VM.

---

## Components
- Resource Group (Ops): `rg-ops-guardrails`
- Automation Account: `aa-ops-guardrails`
- Runbook: `rb-stop-tagged-vms`
- Managed Identity: used for `Connect-AzAccount -Identity`
- Proof VM RG: `rg-proof-autostop`
- Proof VM: `vm-autostop-proof-01`

---

## Runbook Script
File: `infra/stop-tagged-vms.ps1`

Key logic:
- `Get-AzVM -Status`
- filter by tag `AutoStop=0200`
- determine state by:
  - `($_.Code -like "PowerState/*")` and compare against `PowerState/running`
- stop via `Stop-AzVM ... -Force`

---

## Proofs
Proof outputs:
- `proofs/cli/` — jsonc outputs (CLI evidence)
- `proofs/screenshots/` — screenshots (terminal + portal)

### Current clean run (manual trigger)
This repository includes a clean proof run where the VM was verified as running and then deallocated.

CLI proof files:
- `01_rg_show.jsonc`
- `02_vm_show_before.jsonc`
- `03_vm_start.jsonc` (can be empty depending on CLI output; state verified in next step)
- `04_tag_set.jsonc`
- `05_vm_before_running_tagged.jsonc`
- `07_job.<JOB_ID>.jsonc`
- `08_jobstreams.<JOB_ID>.jsonc`
- `09_vm_after.<JOB_ID>.jsonc`

---

## Manual Proof Run — Commands

### Variables
```bash
RG_VM="rg-proof-autostop"
VM_NAME="vm-autostop-proof-01"

RG_OPS="rg-ops-guardrails"
AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
```

## Step 1: Start VM
```bash
az vm start -g "$RG_VM" -n "$VM_NAME" -o jsonc | tee proofs/cli/03_vm_start.jsonc
```

## Step 2: Verify BEFORE (running)
```bash
az vm show -g "$RG_VM" -n "$VM_NAME" -d \
  --query "{name:name, rg:resourceGroup, location:location, power:powerState, tags:tags, publicIp:publicIps}" \
  -o jsonc | tee proofs/cli/02_vm_show_before.jsonc
```

## Step 3: Set tag
```bash
az resource tag -g "$RG_VM" -n "$VM_NAME" \
  --resource-type "Microsoft.Compute/virtualMachines" \
  --tags AutoStop=0200 -o jsonc | tee proofs/cli/04_tag_set.jsonc
  ```

  ## Step 4: Verify BEFORE (running + tagged)
```bash
az vm show -g "$RG_VM" -n "$VM_NAME" -d \
  --query "{name:name, rg:resourceGroup, location:location, power:powerState, tags:tags, publicIp:publicIps}" \
  -o jsonc | tee proofs/cli/05_vm_before_running_tagged.jsonc
```