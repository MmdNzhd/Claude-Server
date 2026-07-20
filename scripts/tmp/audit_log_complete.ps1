$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
$report=@()

function Add($s){ $script:report += $s; Write-Host $s }

# 1) Live bundle version
. "$root\publish\Get-DeployCredentials.ps1"
$pw=Get-SepidzSudoPassword
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$remote=@"
PW=`$(echo $b64 | base64 -d)
printf '%s\n' "`$PW" | sudo -S -p '' cat /usr/local/share/claude-client/connect-version.txt
printf '%s\n' "`$PW" | sudo -S -p '' bash -c 'grep -c Wait-ConnectExit /usr/local/share/claude-client/connect-ui.ps1; grep -c Read-ConnectPrompt /usr/local/share/claude-client/connect-ui.ps1; grep -c Write-ConnectDecision /usr/local/share/claude-client/connect-ui.ps1; grep -c Get-ConnectLogSyncTarget /usr/local/share/claude-client/connect-ui.ps1; grep -c SSH_STAGE /usr/local/share/claude-client/connect-update.ps1; grep -c BOOTSTRAP /usr/local/share/claude-client/connect.bat; grep -c connect_prompt /usr/local/share/claude-client/mac/connect-ui.sh; grep -c DECISION /usr/local/share/claude-client/mac/connect.sh || true'
"@
$out=Join-Path $env:TEMP 'auditlog.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','sepidz@192.168.250.70',($remote -replace "`r",'')) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Add "LIVE:`n$((Get-Content $out -Raw).Trim())"

# 2) Remaining unlogged Read-Host in connect.ps1 (except Wait-ConnectExit internals)
$c=[IO.File]::ReadAllText("$root\scripts\client\windows\connect.ps1")
$rh=[regex]::Matches($c,'Read-Host')
Add "connect.ps1 Read-Host count=$($rh.Count) (expect 0 outside Wait-ConnectExit)"
# Wait-ConnectExit is in connect-ui; connect.ps1 should have 0 Read-Host
Add "connect.ps1 has Wait-ConnectExit refs=$(([regex]::Matches($c,'Wait-ConnectExit')).Count)"
Add "connect.ps1 Write-ConnectDecision=$(([regex]::Matches($c,'Write-ConnectDecision')).Count)"
Add "connect.ps1 Read-ConnectPrompt=$(([regex]::Matches($c,'Read-ConnectPrompt')).Count)"

# 3) Gaps checklist
$ui=[IO.File]::ReadAllText("$root\scripts\client\connect-ui.ps1")
$checks=@{
  'watermark'=($ui -match 'Read-ConnectLogSyncWatermark')
  'session_id'=($ui -match 'ConnectSessionId')
  'sync_every_line'=($ui -match 'ConnectLogLinesSinceSync -ge 1')
  'sync_target_fallback'=($ui -match 'Get-ConnectLogSyncTarget')
  'Wait-ConnectExit'=($ui -match 'function Wait-ConnectExit')
  'Read-ConnectPrompt'=($ui -match 'function Read-ConnectPrompt')
  'Write-ConnectDecision'=($ui -match 'function Write-ConnectDecision')
  'durable_local'=($ui -match 'Get-ConnectLogDayPath')
  'keep_local_on_close'=($ui -match 'Keep durable local')
}
foreach($k in $checks.Keys){ Add ("CHECK {0}={1}" -f $k, $checks[$k]) }

$upd=[IO.File]::ReadAllText("$root\scripts\client\windows\connect-update.ps1")
Add "UPDATE SSH_STAGE=$(([regex]::Matches($upd,'SSH_STAGE')).Count)"
Add "UPDATE silent exit without Write-UpdateFileLog nearby?"
# find exit 0 without UpdateFileLog in previous 3 lines - rough
$lines=$upd -split "`n"
$silent=0
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match '^\s*exit 0\s*$'){
    $window=($lines[[Math]::Max(0,$i-5)..$i] -join ' ')
    if($window -notmatch 'Write-UpdateFileLog|UpdateFileLog'){ $silent++; Add ("  silent@line {0}: {1}" -f ($i+1), $lines[$i].Trim()) }
  }
}
Add "silent_exit0_count=$silent"

$bat=[IO.File]::ReadAllText("$root\scripts\client\windows\connect.bat")
Add "BAT BOOTSTRAP=$($bat -match 'BOOTSTRAP')"

$mac=[IO.File]::ReadAllText("$root\scripts\client\mac\connect.sh")
Add "MAC connect_prompt uses=$(([regex]::Matches($mac,'connect_prompt')).Count)"
Add "MAC connect_decision uses=$(([regex]::Matches($mac,'connect_decision')).Count)"
# raw read -rp left
$rawReads=([regex]::Matches($mac,'(?m)^\s*read -rp ')).Count
Add "MAC raw read -rp left=$rawReads"

Add 'DONE'
$report -join "`n" | Set-Content "$root\scripts\tmp\audit-log-complete.txt" -Encoding UTF8
