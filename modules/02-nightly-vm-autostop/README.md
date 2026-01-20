# Module 02 — Nightly VM Auto-Stop (Tag-Based Guardrail)

This module automatically **deallocates** Azure VMs based on a tag.
Goal: a practical FinOps/Governance guardrail with clean, reproducible proof artifacts.

---

## What it does
- Finds VMs with tag **`AutoStop=0200`**
- Determines power state reliably via **PowerState CODE**
- Deallocates VMs that are currently running

Why this matters:
- `DisplayStatus` can be `"VM running"`
- `Code` is `"PowerState/running"`
Comparing the wrong one can cause the runbook to **skip** a running VM.

---

## Components (names used in this repo)
**Ops / Automation**
- Resource Group: `rg-ops-guardrails`
- Automation Account: `aa-ops-guardrails`
- Runbook: `rb-stop-tagged-vms`
- Auth: Managed Identity (`Connect-AzAccount -Identity`)

**Proof VM**
- Proof RG: `rg-proof-autostop`
- Proof VM: `vm-autostop-proof-01`
- Tag used: `AutoStop=0200`

---

## Runbook Script
File: `infra/stop-tagged-vms.ps1`

Key logic:
- `Get-AzVM -Status` to list VMs
- Filter by tag `AutoStop=0200`
- Refresh per-VM status via `Get-AzVM ... -Status`
- Extract `PowerState/*` from `.Statuses[].Code`
- Compare against `PowerState/running`
- Stop (deallocate) via `Stop-AzVM ... -Force`

---

## Proof artifacts
## Proof run (latest clean manual run)

This section links the **exact artifacts** of the latest clean proof run:
- CLI outputs (`proofs/cli/*.jsonc`)
- Screenshots (`proofs/screenshots/*.png`)

> Tip: In GitHub you can click the links. Images render inline.

### Evidence map (Step → CLI proof → Screenshot)

| Step | What you prove | CLI proof | Screenshot |
|---:|---|---|---|
| 1 | Proof RG exists | [`proofs/cli/01_rg_show.jsonc`](./proofs/cli/01_rg_show.jsonc) | [`proofs/screenshots/01_rg_show.png`](./proofs/screenshots/01_rg_show.png) |
| 2 | VM BEFORE (state) | [`proofs/cli/02_vm_show_before.jsonc`](./proofs/cli/02_vm_show_before.jsonc) | *(optional / if you captured it)* |
| 3 | VM started (command executed) | [`proofs/cli/03_vm_start.jsonc`](./proofs/cli/03_vm_start.jsonc) | [`proofs/screenshots/02_vm_start.png`](./proofs/screenshots/02_vm_start.png) |
| 4 | Tag set (`AutoStop=0200`) | [`proofs/cli/04_tag_set.jsonc`](./proofs/cli/04_tag_set.jsonc) | [`proofs/screenshots/03_tag_set.png`](./proofs/screenshots/03_tag_set.png) |
| 5 | BEFORE (running + tagged) | [`proofs/cli/05_vm_before_running_tagged.jsonc`](./proofs/cli/05_vm_before_running_tagged.jsonc) | [`proofs/screenshots/04_vm_before_running_tagged.png`](./proofs/screenshots/04_vm_before_running_tagged.png) |
| 6 | Runbook started (job id) | [proofs/cli/07_job.a2fb2af2-9282-4054-86ad-d8bb0e300b26.jsonc](./proofs/cli/07_job.a2fb2af2-9282-4054-86ad-d8bb0e300b26.jsonc) | [`proofs/screenshots/05_runbook_start_jobid.png`](./proofs/screenshots/05_runbook_start_jobid.png) |
| 7 | Job status (Running/Completed) | [proofs/cli/07_job.a2fb2af2-9282-4054-86ad-d8bb0e300b26.jsonc](./proofs/cli/07_job.a2fb2af2-9282-4054-86ad-d8bb0e300b26.jsonc) | [`proofs/screenshots/06_job_show.png`](./proofs/screenshots/06_job_show.png) |
| 8 | Streams show deallocate happened | [proofs/cli/08_jobstreams.a2fb2af2-9282-4054-86ad-d8bb0e300b26.jsonc](./proofs/cli/08_jobstreams.a2fb2af2-9282-4054-86ad-d8bb0e300b26.jsonc) | [`proofs/screenshots/07_jobstreams_ok.png`](./proofs/screenshots/07_jobstreams_ok.png) |
| 9 | AFTER (VM deallocated) | [proofs/cli/09_vm_after.a2fb2af2-9282-4054-86ad-d8bb0e300b26.jsonc](./proofs/cli/09_vm_after.a2fb2af2-9282-4054-86ad-d8bb0e300b26.jsonc) | [`proofs/screenshots/08_vm_after_deallocated.png`](./proofs/screenshots/08_vm_after_deallocated.png) |
| 10 | Portal confirmation | — | [`proofs/screenshots/09_portal_vm_deallocated.png`](./proofs/screenshots/09_portal_vm_deallocated.png) |

### Screenshots (inline)

#### 01 — Proof RG
![01_rg_show](./proofs/screenshots/01_rg_show.png)

#### 02 — Start VM
![02_vm_start](./proofs/screenshots/02_vm_start.png)

#### 03 — Set tag AutoStop=0200
![03_tag_set](./proofs/screenshots/03_tag_set.png)

#### 04 — Verify BEFORE (running + tagged)
![04_vm_before_running_tagged](./proofs/screenshots/04_vm_before_running_tagged.png)

#### 05 — Runbook start (job id)
![05_runbook_start_jobid](./proofs/screenshots/05_runbook_start_jobid.png)

#### 06 — Job show
![06_job_show](./proofs/screenshots/06_job_show.png)

#### 07 — Job streams OK (deallocate evidence)
![07_jobstreams_ok](./proofs/screenshots/07_jobstreams_ok.png)

#### 08 — VM AFTER (deallocated)
![08_vm_after_deallocated](./proofs/screenshots/08_vm_after_deallocated.png)

#### 09 — Portal VM deallocated
![09_portal_vm_deallocated](./proofs/screenshots/09_portal_vm_deallocated.png)

---

## Manual proof run — step-by-step commands

> Run from:
> `modules/02-nightly-vm-autostop/`

### Step 0 — Set variables
```bash
cd ~/azure-finops-governance-guardrails/modules/02-nightly-vm-autostop
mkdir -p proofs/cli proofs/screenshots

RG_VM="rg-proof-autostop"
VM_NAME="vm-autostop-proof-01"

RG_OPS="rg-ops-guardrails"
AA_NAME="aa-ops-guardrails"
RUNBOOK_NAME="rb-stop-tagged-vms"
```

### Step 1 — Show proof RG (sanity + proof)
```bash
az group show -n "$RG_VM" -o jsonc | tee proofs/cli/01_rg_show.jsonc
```

### Step 2 — Verify VM BEFORE (capture current state)
```bash
az vm show -g "$RG_VM" -n "$VM_NAME" -d \
  --query "{name:name, rg:resourceGroup, location:location, power:powerState, tags:tags, publicIp:publicIps}" \
  -o jsonc | tee proofs/cli/02_vm_show_before.jsonc
```

### Step 3 — Start VM (proof file may be empty)
```bash
az vm start -g "$RG_VM" -n "$VM_NAME" -o jsonc | tee proofs/cli/03_vm_start.jsonc
```

### Step 4 — Set tag AutoStop=0200
```bash
az resource tag -g "$RG_VM" -n "$VM_NAME" \
  --resource-type "Microsoft.Compute/virtualMachines" \
  --tags AutoStop=0200 -o jsonc | tee proofs/cli/04_tag_set.jsonc
```

### Step 5 — Verify BEFORE (running + tagged)
```bash
az vm show -g "$RG_VM" -n "$VM_NAME" -d \
  --query "{name:name, rg:resourceGroup, location:location, power:powerState, tags:tags, publicIp:publicIps}" \
  -o jsonc | tee proofs/cli/05_vm_before_running_tagged.jsonc
```

### Step 6 — Start runbook (manual trigger)
```bash
JOB_ID=$(az automation runbook start -g "$RG_OPS" --automation-account-name "$AA_NAME" -n "$RUNBOOK_NAME" --query jobId -o tsv)
echo "$JOB_ID"
```

### Step 7 — Save job metadata
```bash
az automation job show -g "$RG_OPS" --automation-account-name "$AA_NAME" -n "$JOB_ID" -o jsonc \
  | tee "proofs/cli/07_job.$JOB_ID.jsonc" >/dev/null
```

### Step 8 — Save job streams (REST is most reliable)
```bash
SUB_ID=$(az account show --query id -o tsv)

az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Automation/automationAccounts/$AA_NAME/jobs/$JOB_ID/streams?api-version=2024-10-23" \
  -o jsonc | tee "proofs/cli/08_jobstreams.$JOB_ID.jsonc" >/dev/null
```

Optional: extract key log lines
```bash
grep -nE "Connected|Found|state:|Dealloc|Deallocated|Skip|Error|Exception" "proofs/cli/08_jobstreams.$JOB_ID.jsonc" | head -n 200
```

Expected stream sequence:
- Found 1 VM(s) with tag AutoStop=0200
- state: PowerState/running
- Deallocating ...
- Deallocated ...

### Step 9 — Verify AFTER (deallocated)
```bash
az vm show -g "$RG_VM" -n "$VM_NAME" -d \
  --query "{name:name, power:powerState, tags:tags}" \
  -o jsonc | tee "proofs/cli/09_vm_after.$JOB_ID.jsonc"
```

---

## Lessons learned / pitfalls (real-world)
1) DisplayStatus vs Code mismatch  
- DisplayStatus: "VM running"  
- Code: "PowerState/running"  
- Fix: compare PowerState/* Code  

2) CLI automation commands are experimental  
- Warnings are expected  
- Streams are most reliably collected via `az rest`  

3) API versions can break  
- Not every api-version works for every endpoint  
- For job streams, `2024-10-23` was validated in this proof run  

4) JobSchedule conflicts during deployment  
- Conflict: A jobSchedule with same id already exists.  
- Meaning: deploy tries to create a schedule that already exists  
- Fix: cleanup old schedules or ensure deploy generates/looks up IDs safely     
```
---

## Security note (RBAC scope)
For this learning module, the Automation Account’s managed identity is granted **Virtual Machine Contributor**
at **subscription scope** to keep the setup simple and reproducible.

In production (especially regulated / FinTech environments), this scope is **too broad**.
Preferred approach:
- restrict scope to a dedicated RG/subscription for workloads, and/or
- use a **custom role** with least privilege (only the actions needed to **read VM state + deallocate** tagged VMs).



