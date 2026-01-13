$ErrorActionPreference = "Stop"

$tagAutoStopKey   = "autoStop"
$tagAutoStopValue = "true"
$tagEnvKey        = "environment"
$tagEnvValue      = "lab"

Connect-AzAccount -Identity | Out-Null

$ctx = Get-AzContext
Write-Output ("Connected as Managed Identity. Subscription: {0}" -f $ctx.Subscription.Id)

$tags = @{
  $tagAutoStopKey = $tagAutoStopValue
  $tagEnvKey      = $tagEnvValue
}

$vms = Get-AzResource -ResourceType "Microsoft.Compute/virtualMachines" -Tag $tags

if (-not $vms -or $vms.Count -eq 0) {
  Write-Output "No VMs matched tags autoStop=true AND environment=lab. Nothing to do."
  return
}

Write-Output ("Matched VMs: {0}" -f $vms.Count)

foreach ($vm in $vms) {
  $rg = $vm.ResourceGroupName
  $name = $vm.Name
  Write-Output ("Stopping (deallocate) VM: {0} in RG: {1}" -f $name, $rg)
  Stop-AzVM -ResourceGroupName $rg -Name $name -Force | Out-Null
  Write-Output ("Stopped VM: {0}" -f $name)
}
