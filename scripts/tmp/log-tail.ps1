$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
Write-Output '=== fd102 session start ==='
Select-String -Path $log -Pattern 'fd102c09b242.*session start|session start.*fd102c09b242' | ForEach-Object { $_.Line }
Write-Output '=== acquired pid (exact) ==='
Select-String -Path $log -Pattern 'SINGLE_INSTANCE: acquired pid=' | ForEach-Object { $_.Line }
Write-Output '=== 82924 any ==='
Select-String -Path $log -Pattern '82924' | ForEach-Object { $_.Line }
Write-Output '=== last 15 lines ==='
Get-Content $log -Tail 15
