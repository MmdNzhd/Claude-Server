Write-Output '=== connect-related processes ==='
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'connect\.ps1|connect-design|connect-ui|connect\.bat') } |
  Select-Object ProcessId, @{N='Start';E={$_.CreationDate}}, CommandLine |
  Sort-Object ProcessId |
  Format-List

Write-Output '=== sessions.index tail ==='
$idx = Join-Path $env:USERPROFILE '.config\claude-connect\logs\sessions.index'
if (Test-Path $idx) { Get-Content $idx -Tail 15 }
