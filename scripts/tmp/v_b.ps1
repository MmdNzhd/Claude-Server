$ErrorActionPreference='Continue'
Write-Host '=== remote bundle markers ==='
ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=no smart@192.168.250.70 "grep -c LastConnectLogSyncOk /usr/local/share/claude-client/connect-ui.ps1; grep -c 'ConnectLogLinesSinceSync -ge 25' /usr/local/share/claude-client/connect-ui.ps1; grep -c 'function Sync-ConnectLogToServer' /usr/local/share/claude-client/connect-ui.ps1; grep -c 'same folder as connect.bat' /usr/local/share/claude-client/connect.ps1; grep -c 'TRACE/DEBUG stay local' /usr/local/share/claude-client/connect-ui.ps1"
Write-Host '=== server log completeness ==='
ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=no smart@192.168.250.70 "wc -c ~/.claude/logs/connect-20260719.log; grep -c BOOTSTRAP ~/.claude/logs/connect-20260719.log; grep -c 'session start' ~/.claude/logs/connect-20260719.log; grep -c 'DECISION: project_select' ~/.claude/logs/connect-20260719.log; grep -c 'SESSION_LOOP begin' ~/.claude/logs/connect-20260719.log; head -n1 ~/.claude/logs/connect-20260719.log"
Write-Host '=== local log ==='
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$item = Get-Item $local
Write-Host ("bytes={0} lines={1}" -f $item.Length, (Get-Content $local | Measure-Object -Line).Lines)
foreach ($pat in @('BOOTSTRAP: connect.bat start','session start v20260719','DECISION: project_select','SESSION_LOOP begin','LAUNCH begin')) {
  $n = (Select-String -Path $local -SimpleMatch $pat | Measure-Object).Count
  Write-Host ("local {0} => {1}" -f $pat, $n)
}
Write-Host 'B done'
