$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
foreach ($sid in @('fd102c09b242','82924','56492','cc33e300bca1','c7c460072bce')) {
  Write-Output "=== $sid ==="
  Select-String -Path $log -Pattern $sid | Select-Object -First 8 | ForEach-Object { $_.Line }
}
Write-Output '=== fd102 MULTI/SINGLE ==='
Select-String -Path $log -Pattern 'fd102c09b242' | Select-String -Pattern 'SINGLE_INSTANCE|MULTI_INSTANCE' | ForEach-Object { $_.Line }
Write-Output '=== v20260720.12 starts ==='
Select-String -Path $log -Pattern 'v20260720.12' | Select-Object -First 5 | ForEach-Object { $_.Line }
