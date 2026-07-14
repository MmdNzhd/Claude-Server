# test-connect-diagnostic.ps1 - verdict codes for single-run diagnosis
# Callers: scripts/client/tests/run-all.ps1
# Imports: connect-diagnostic.ps1 (Get-ConnectProblemVerdict, Write-ConnectDiagnosticReport)
# User request: "More complete, more precise log - I need to know exactly what the problem is from a single run"
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

. (Get-ClientFile 'connect-diagnostic.ps1')

Write-Host ''
Write-Host '=== Connect diagnostic ===' -ForegroundColor Cyan
Write-Host ''

Assert (Get-Command Get-ConnectProblemVerdict -ErrorAction SilentlyContinue) 'Get-ConnectProblemVerdict defined'
Assert (Get-Command Write-ConnectDiagnosticReport -ErrorAction SilentlyContinue) 'Write-ConnectDiagnosticReport defined'

$v = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $false; Port = 21004; ServerReachable = $true; MountOk = $true
    EditorCmd = 'cursor'; OnFolder = $false; AgentHome = $false; WindowOpen = $false
    CursorExeFound = $true; AuthOk = $true; MountPoint = 'yes'; PathExists = 'yes'
}
Assert ($v.Code -eq 'TUNNEL_DOWN') 'detects TUNNEL_DOWN'
Assert ($v.NextAction -eq 'R') 'TUNNEL_DOWN suggests R'

$v = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $false; MountOut = 'No such file or directory'
    ServerReachable = $true; EditorCmd = 'cursor'; CursorExeFound = $true
    OnFolder = $false; MountPoint = 'no'; PathExists = 'no'
}
Assert ($v.Code -eq 'MOUNT_PATH_MISSING') 'detects MOUNT_PATH_MISSING'

$v = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $true; MountPoint = 'yes'; PathExists = 'yes'
    EditorCmd = 'cursor'; CursorExeFound = $true; AuthOk = $true
    OnFolder = $false; AgentHome = $true; WindowOpen = $true; DidLaunch = $true
    LaunchHistory = '1:folder-uri:folder=False:agent=True'
}
Assert ($v.Code -eq 'CURSOR_AGENT_HOME') 'detects CURSOR_AGENT_HOME from launch history'

$v = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $true; MountPoint = 'yes'; PathExists = 'yes'
    EditorCmd = 'cursor'; CursorExeFound = $true; AuthOk = $true
    OnFolder = $true; AgentHome = $false; WindowOpen = $true
}
Assert ($v.Code -eq 'CURSOR_ON_FOLDER_OK') 'detects CURSOR_ON_FOLDER_OK'

$diagSrc = Get-Content (Get-ClientFile 'connect-diagnostic.ps1') -Raw
Assert ($diagSrc -match 'lightDiag = \(\$Phase -eq ''SESSION_OPEN''') 'F7 light SESSION_OPEN diagnostic gate'
Assert ($diagSrc -match 'skipped=light_session_open') 'F7 skips expensive process snapshot'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
