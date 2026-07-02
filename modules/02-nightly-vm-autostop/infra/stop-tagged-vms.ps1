param()

$TagName  = "AutoStop"
$TagValue = "0200"

# The guardrail is intentionally limited to this dedicated lab resource group.
$TargetResourceGroup = "rg-finops-lab"

Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity | Out-Null

$ctx = Get-AzContext
Write-Output ("Connected. Subscription: {0}" -f $ctx.Subscription.Id)
Write-Output ("Target Resource Group: {0}" -f $TargetResourceGroup)

# Only retrieve VMs from the dedicated FinOps lab resource group.
$vms = Get-AzVM -ResourceGroupName $TargetResourceGroup -Status

$targets = $vms | Where-Object {
    $_.Tags -and (
        $_.Tags.GetEnumerator() |
        Where-Object {
            $_.Key.Trim() -ieq $TagName -and
            ("" + $_.Value).Trim() -eq $TagValue
        } |
        Select-Object -First 1
    )
}

Write-Output (
    "Found {0} VM(s) in {1} with tag {2}={3}" -f
    $targets.Count,
    $TargetResourceGroup,
    $TagName,
    $TagValue
)

foreach ($vm in $targets) {
    $vmStatus = Get-AzVM `
        -ResourceGroupName $vm.ResourceGroupName `
        -Name $vm.Name `
        -Status

    $power = $vmStatus.Statuses |
        Where-Object { $_.Code -like "PowerState/*" } |
        Select-Object -First 1

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
            -Force |
            Out-Null

        Write-Output (
            "Deallocated VM {0}/{1}" -f
            $vm.ResourceGroupName,
            $vm.Name
        )
    }
    else {
        Write-Output (
            "Skip VM {0}/{1} (not running)" -f
            $vm.ResourceGroupName,
            $vm.Name
        )
    }
}