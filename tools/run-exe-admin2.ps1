$ErrorActionPreference = 'Continue'
$exe = 'C:\Users\Smart\Downloads\claude-code-client-20260715.QUARANTINE-DO-NOT-RUN-20260721-214141\windows\Claude-Connect.exe'
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'

Write-Host '=== identity / elevation ==='
$who = whoami /groups | Select-String 'S-1-5-32-544|High Mandatory'
$who | ForEach-Object { $_.Line }
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p = New-Object Security.Principal.WindowsPrincipal($id)
Write-Host ("IsInRole Admin={0}" -f $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

Write-Host '=== zone / unblock ==='
Get-Item $exe -Stream * -ErrorAction SilentlyContinue | Format-Table Stream, Length
Unblock-File -LiteralPath $exe -ErrorAction SilentlyContinue
Write-Host 'unblocked'

function Try-Launch([string]$Path, [string]$Label, [switch]$RunAs) {
  Write-Host ("=== try {0} runas={1} ===" -f $Label, [bool]$RunAs)
  try {
    if ($RunAs) {
      $proc = Start-Process -FilePath $Path -WorkingDirectory (Split-Path $Path) -Verb RunAs -PassThru
    } else {
      $proc = Start-Process -FilePath $Path -WorkingDirectory (Split-Path $Path) -PassThru
    }
    Write-Host ("OK pid={0}" -f $proc.Id)
    Start-Sleep -Seconds 2
    return $true
  } catch {
    Write-Host ("FAIL {0}" -f $_.Exception.Message)
    return $false
  }
}

# 1) quarantine normal
[void](Try-Launch $exe 'quarantine' )
# 2) quarantine RunAs
[void](Try-Launch $exe 'quarantine' -RunAs)
# 3) desktop RunAs (known good)
[void](Try-Launch $desk 'desktop' -RunAs)

# 4) elevated via schtasks (no interactive UAC if already elevated helper exists)
Write-Host '=== schtasks elevate quarantine ==='
$task = 'ClaudeConnectQuarantineLaunch'
$arg = '/c start "" /D "{0}" "{1}"' -f (Split-Path $exe), $exe
try { schtasks /Delete /TN $task /F 2>$null | Out-Null } catch {}
# Run with highest privileges
$create = schtasks /Create /TN $task /TR ("cmd.exe {0}" -f $arg) /SC ONCE /ST 00:00 /RL HIGHEST /F
Write-Host ("create: {0}" -f ($create -join ' '))
$run = schtasks /Run /TN $task
Write-Host ("run: {0}" -f ($run -join ' '))
Start-Sleep -Seconds 4
try { schtasks /Delete /TN $task /F 2>$null | Out-Null } catch {}

Write-Host '=== processes ==='
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $cl = [string]$_.CommandLine
  $cl -match 'Claude-Connect|connect-boot\.ps1|connect\.bat|setup-launch'
} | ForEach-Object {
  $c = [string]$_.CommandLine
  if ($c.Length -gt 180) { $c = $c.Substring(0,180) + '...' }
  Write-Host ("pid={0} {1}" -f $_.ProcessId, $c)
}
