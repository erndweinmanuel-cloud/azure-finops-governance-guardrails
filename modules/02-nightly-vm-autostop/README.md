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
Folders:
- `proofs/cli/` — jsonc proof outputs (CLI evidence)
- `proofs/screenshots/` — screenshots (terminal + portal)

This repo contains a **clean manual proof run** showing:
- VM is running + tagged BEFORE
- Runbook runs and logs “Deallocating … / Deallocated …”
- VM is deallocated AFTER

### CLI proof files (latest clean manual run)
- `01_rg_show.jsonc`
- `02_vm_show_before.jsonc`
- `03_vm_started_verify.jsonc`
- `04_tag_set.jsonc`
- `05_vm_before_running_tagged.jsonc`
- `07_job.<JOB_ID>.jsonc`
- `08_jobstreams.<JOB_ID>.jsonc`
- `09_vm_after.<JOB_ID>.jsonc`

### Screenshot naming (recommended)
Store screenshots in: `proofs/screenshots/`

Suggested names:
- `01_rg_show.png`
- `02_vm_show_before.png`
- `03_vm_started_verify.png`
- `04_tag_set.png`
- `05_vm_before_running_tagged.png`
- `06_runbook_start_jobid.png`
- `07_job_show.png`
- `08_jobstreams_ok.png`
- `09_portal_vm_deallocated.png`

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

### Step 3 — Start VM + verify started (proof)
Note: `az vm start` often returns no JSON output. We prove state with the next command.
```bash
az vm start -g "$RG_VM" -n "$VM_NAME" -o none

az vm show -g "$RG_VM" -n "$VM_NAME" -d \
  --query "{name:name, power:powerState}" \
  -o jsonc | tee proofs/cli/03_vm_started_verify.jsonc
```

### Step 4 — Set tag AutoStop=0200 (robust via resource-id)
```bash
VM_ID=$(az vm show -g "$RG_VM" -n "$VM_NAME" --query id -o tsv)

az tag create --resource-id "$VM_ID" --tags AutoStop=0200 -o jsonc \
  | tee proofs/cli/04_tag_set.jsonc
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

### Step 7 — Wait for job completion + save job metadata
```bash
while true; do
  STATUS=$(az automation job show -g "$RG_OPS" --automation-account-name "$AA_NAME" -n "$JOB_ID" --query status -o tsv)
  echo "Job status: $STATUS"
  [[ "$STATUS" == "Completed" || "$STATUS" == "Failed" || "$STATUS" == "Stopped" ]] && break
  sleep 5
done
```

```bash
az automation job show -g "$RG_OPS" --automation-account-name "$AA_NAME" -n "$JOB_ID" -o jsonc \
  | tee "proofs/cli/07_job.$JOB_ID.jsonc" >/dev/null
```

### Step 8 — Save job streams (REST is most reliable)
Azure CLI automation is experimental; job streams are most reliable via `az rest`.

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

Expected:
- BEFORE: VM running
- Streams: PowerState/running → Deallocating → Deallocated
- AFTER: VM deallocated

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
