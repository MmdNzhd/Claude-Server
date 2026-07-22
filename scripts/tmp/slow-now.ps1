$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Write-Host ("LOG_SIZE=" + (Get-Item $log).Length)
Write-Host '=== LATEST SESSION STARTS ==='
Select-String -Path $log -Pattern 'session start v|BOOTSTRAP:|MULTI_INSTANCE:|SINGLE_INSTANCE:' |
  Select-Object -Last 20 | ForEach-Object { $_.Line }

# find latest session id
$starts = Select-String -Path $log -Pattern 'session start v' | Select-Object -Last 1
Write-Host "=== LATEST START LINE ==="
Write-Host $starts.Line
if ($starts.Line -match '\[([a-f0-9]{12})\]') { $sid = $Matches[1] } else { $sid = $null }
Write-Host "SID=$sid"

if ($sid) {
  Write-Host "=== STEP ENDS for $sid ==="
  Select-String -Path $log -Pattern "\[$sid\].*(STEP end:|PUSH_CONF|ACQUIRE_|ENSURE_TUNNEL|HOSTKEY_FP|foreign|Server setup|Loading projects|Opening Cursor|Mounting)" |
    ForEach-Object { $_.Line }

  Write-Host "=== SLOW SSH (>1500ms) for $sid ==="
  Select-String -Path $log -Pattern "\[$sid\].*SSH_END exit=.*ms=" |
    ForEach-Object {
      if ($_.Line -match 'ms=(\d+)') {
        $ms = [int]$Matches[1]
        if ($ms -ge 1500) { $_.Line }
      }
    }
}
