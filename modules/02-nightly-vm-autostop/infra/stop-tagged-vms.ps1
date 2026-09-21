param()

$ErrorActionPreference = "Stop"

$TagName  = "AutoStop"
$TagValue = "0200"

# Shared FinOps lab target scope.
# Module 02 consumes this Resource Group but does not own it.
$TargetResourceGroup = "rg-finops-lab"

try {
    Write-Output "Authenticating with system-assigned Managed Identity..."

    Disable-AzContextAutosave -Scope Process | Out-Null

    Connect-AzAccount `
        -Identity `
        -ErrorAction Stop |
        Out-Null

    $ctx = Get-AzContext -ErrorAction Stop

    if (
        $null -eq $ctx -or
        $null -eq $ctx.Subscription -or
        [string]::IsNullOrWhiteSpace($ctx.Subscription.Id)
    ) {
        throw "Managed Identity authenticated, but no Azure subscription context is available."
    }

    $SubscriptionId = $ctx.Subscription.Id

    Write-Output ("Connected. Subscription: {0}" -f $SubscriptionId)
    Write-Output ("Target Resource Group: {0}" -f $TargetResourceGroup)

    Write-Output "Discovering virtual machines..."

    $vms = @(
        Get-AzVM `
            -ResourceGroupName $TargetResourceGroup `
            -Status `
            -ErrorAction Stop
    )

    $targets = @(
        $vms | Where-Object {
            $_.Tags -and (
                $_.Tags.GetEnumerator() |
                Where-Object {
                    $_.Key.Trim() -ieq $TagName -and
                    ("" + $_.Value).Trim() -eq $TagValue
                } |
                Select-Object -First 1
            )
        }
    )

    Write-Output (
        "Found {0} VM(s) in {1} with tag {2}={3}" -f
        $targets.Count,
        $TargetResourceGroup,
        $TagName,
        $TagValue
    )

    foreach ($vm in $targets) {
        Write-Output (
            "Checking VM {0}/{1}..." -f
            $vm.ResourceGroupName,
            $vm.Name
        )

        $vmStatus = Get-AzVM `
            -ResourceGroupName $vm.ResourceGroupName `
            -Name $vm.Name `
            -Status `
            -ErrorAction Stop

        $power = $vmStatus.Statuses |
            Where-Object { $_.Code -like "PowerState/*" } |
            Select-Object -First 1

        if ($null -eq $power -or [string]::IsNullOrWhiteSpace($power.Code)) {
            throw (
                "Could not determine power state for VM {0}/{1}." -f
                $vm.ResourceGroupName,
                $vm.Name
            )
        }

        $state = $power.Code

        Write-Output (
            "VM {0}/{1} state: {2}" -f
            $vm.ResourceGroupName,
            $vm.Name,
            $state
        )

        if ($state -eq "PowerState/running") {
            Write-Output (
                "Deallocating VM {0}/{1}..." -f
                $vm.ResourceGroupName,
                $vm.Name
            )

            Stop-AzVM `
                -ResourceGroupName $vm.ResourceGroupName `
                -Name $vm.Name `
                -Force `
                -ErrorAction Stop |
                Out-Null

            Write-Output (
                "Deallocated VM {0}/{1}" -f
                $vm.ResourceGroupName,
                $vm.Name
            )
        }
        else {
            Write-Output (
                "Skip VM {0}/{1} (state: {2})" -f
                $vm.ResourceGroupName,
                $vm.Name,
                $state
            )
        }
    }

    Write-Output "AutoStop guardrail completed successfully."
}
catch {
    Write-Error (
        "AutoStop guardrail failed: {0}" -f
        $_.Exception.Message
    )

    throw
}
