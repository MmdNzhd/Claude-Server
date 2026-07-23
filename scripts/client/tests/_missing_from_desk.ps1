$ErrorActionPreference = 'Stop'
# Compare HEAD (.24) vs current (.40 desk) for test-critical strings
$headPath = Join-Path $env:TEMP 'connect-head.ps1'
Push-Location 'D:\Smart\Claude-Code-Server'
git show HEAD:scripts/client/windows/connect.ps1 | Out-File -Encoding utf8 $headPath
Pop-Location
$head = [IO.File]::ReadAllText($headPath)
$cur = [IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')
$need = @(
  'session_open_summary','ConnectPerf','RECOVERY_SKIP_CLEAR_MOUNT','FINALLY_KEEP_TUNNEL',
  'Start-ProcessAsInteractiveUser','Global\\ClaudeConnect','FAIL NEED_ADMIN','FAIL STEP',
  'FAIL ADMIN_UAC','Write-ConnectUserFacingError','Wait-ConnectExit',
  'HERE_NOTRAIL','connect-boot.ps1','auth_folder_check'
)
Write-Host 'string | HEAD24 | CUR40'
foreach ($s in $need) {
  Write-Host ("{0} | {1} | {2}" -f $s, ($head.Contains($s)), ($cur.Contains($s)))
}
Write-Host ("head_ver=" + $(if($head -match "ConnectVersion = '([^']+)'"){$Matches[1]}else{'?'}))
Write-Host ("cur_ver=" + $(if($cur -match "ConnectVersion = '([^']+)'"){$Matches[1]}else{'?'}))
Write-Host ("head_len=$($head.Length) cur_len=$($cur.Length)")
