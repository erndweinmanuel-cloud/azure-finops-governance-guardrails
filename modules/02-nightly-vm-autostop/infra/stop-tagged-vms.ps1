param()

$TagName  = "AutoStop"
$TagValue = "0200"

Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity | Out-Null

$ctx = Get-AzContext
Write-Output ("Connected. Subscription: {0}" -f $ctx.Subscription.Id)

$vms = Get-AzVM -Status

$targets = $vms | Where-Object {
    $_.Tags -and (
        $_.Tags.GetEnumerator() |
        Where-Object {
            $_.Key.Trim() -ieq $TagName -and ("" + $_.Value).Trim() -eq $TagValue
        } |
        Select-Object -First 1
    )
}

Write-Output ("Found {0} VM(s) with tag {1}={2}" -f $targets.Count, $TagName, $TagValue)

foreach ($vm in $targets) {
    $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
    $power    = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -First 1)
    $state    = $power.Code

    Write-Output ("VM {0}/{1} state: {2}" -f $vm.ResourceGroupName, $vm.Name, $state)

    if ($state -eq "PowerState/running") {
        Write-Output ("Deallocating VM {0}/{1}..." -f $vm.ResourceGroupName, $vm.Name)
        Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force | Out-Null
        Write-Output ("Deallocated VM {0}/{1}" -f $vm.ResourceGroupName, $vm.Name)
    } else {
        Write-Output ("Skip VM {0}/{1} (not running)" -f $vm.ResourceGroupName, $vm.Name)
    }
}
