# deep-audit-live.ps1 - live WMI budget audit on Windows
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
if ($env:OS -notmatch 'Windows') { Write-Host 'SKIP not Windows'; exit 0 }
. (Get-ClientFile 'connect-ui.ps1')
. (Get-ClientFile 'editor-launch.ps1')

$alias = 'claude-server'
$path = '/home/smart/mounts/okr-jira'
$fail = 0
function Row($label, $ms, $cim, $extra='') {
    Write-Host ("  {0,-32} {1,6} ms  cim={2,-3} {3}" -f $label, $ms, $cim, $extra)
}

Write-Host ''
Write-Host '=== Live WMI budget audit ===' -ForegroundColor Cyan
Write-Host "Path: $path"
Write-Host ''

# Simulate auth block (connect.ps1:1301-1306)
Clear-CursorProcessCache; $script:LaunchCimCallCount = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
$w = Test-RemoteEditorWindowOpen -EditorCmd 'cursor' -Alias $alias -RemotePath $path
$on = Test-RemoteEditorOnCorrectFolder -EditorCmd 'cursor' -Alias $alias -RemotePath $path
$ag = Test-RemoteEditorInAgentHome
$diag = Get-RemoteEditorLaunchDiag -EditorCmd 'cursor' -Alias $alias -RemotePath $path
$sw.Stop()
Row 'auth_block_folder_check' $sw.ElapsedMilliseconds $script:LaunchCimCallCount "on=$on window=$w"

# Launch with KnownOnFolder (primary open path)
Clear-CursorProcessCache; $script:LaunchCimCallCount = 0
$sw2 = [Diagnostics.Stopwatch]::StartNew()
$ok = Launch-RemoteEditor -EditorCmd 'cursor' -Alias $alias -RemotePath $path -KnownOnFolder:$on
$sw2.Stop()
Row 'launch_known_on_folder' $sw2.ElapsedMilliseconds $script:LaunchCimCallCount "ok=$ok"

# Launch without KnownOnFolder (hotkey O / relaunch path)
Clear-CursorProcessCache; $script:LaunchCimCallCount = 0
$sw3 = [Diagnostics.Stopwatch]::StartNew()
$ok2 = Launch-RemoteEditor -EditorCmd 'cursor' -Alias $alias -RemotePath $path
$sw3.Stop()
Row 'launch_no_known_on_folder' $sw3.ElapsedMilliseconds $script:LaunchCimCallCount "ok=$ok2"

# Verbose gate check
$vl = $script:VerboseLaunch
Row 'verbose_launch_flag' 0 $(if($vl){1}else{0}) "enabled=$vl"

Write-Host ''
$gates = @(
    ($sw2.ElapsedMilliseconds -lt 1500),
    ($script:LaunchCimCallCount -le 8 -or $ok2)
)
if (-not $gates[0]) { $fail++ ; Write-Host 'FAIL skip path >= 1500ms' -ForegroundColor Red }
else { Write-Host 'PASS skip path < 1500ms' -ForegroundColor Green }
if ($sw3.ElapsedMilliseconds -lt 1500 -and $on) {
    Write-Host "INFO relaunch path also fast ($($sw3.ElapsedMilliseconds) ms) because on_folder skip triggers" -ForegroundColor DarkGray
}
Write-Host ''
exit $fail
