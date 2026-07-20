$ErrorActionPreference='Continue'
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')

Write-Host '=== BOOTSTRAP to session (13:44) ==='
Select-String -Path $today -Pattern '13:44:|13:45:' |
  Where-Object { $_.Line -match 'BOOTSTRAP|UPDATE|session start|SINGLE_INSTANCE|available|up_to_date|applied|SSH_STAGE' } |
  ForEach-Object { $_.Line.Substring(0,[Math]::Min(200,$_.Line.Length)) }

Write-Host ''
Write-Host '=== any newer session after b25? ==='
Select-String -Path $today -Pattern 'session start v' | Select-Object -Last 5 | ForEach-Object { $_.Line }

Write-Host ''
Write-Host '=== file mtime / size now ==='
$i = Get-Item $today
Write-Host ("size={0} mtime={1}" -f $i.Length, $i.LastWriteTime)

Write-Host ''
Write-Host '=== live processes again ==='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect' } |
  ForEach-Object {
    Write-Host ("PID={0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(180,$_.CommandLine.Length)))
  }

# Why SSH ~1.2s each - check if ControlMaster used in Invoke-SshXCore
Write-Host ''
Write-Host '=== does Invoke-SshXCore use ControlMaster? ==='
Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'ControlMaster|ControlPath|ControlPersist|function Invoke-SshX' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
