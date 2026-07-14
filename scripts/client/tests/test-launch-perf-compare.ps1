# test-launch-perf-compare.ps1 - live compare WMI detect vs KnownOnFolder (Windows)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
if ($env:OS -notmatch 'Windows') { Write-Host 'SKIP not Windows'; exit 0 }
. (Get-ClientFile 'connect-ui.ps1')
. (Get-ClientFile 'editor-launch.ps1')
$alias = 'claude-server'
$path = '/home/smart/mounts/okr-jira'
Clear-CursorProcessCache; $script:LaunchCimCallCount = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
$on = Test-RemoteEditorOnCorrectFolder -EditorCmd 'cursor' -Alias $alias -RemotePath $path
$sw.Stop()
Write-Host "detect_only ms=$($sw.ElapsedMilliseconds) cim=$($script:LaunchCimCallCount) on_folder=$on"
if (-not $on) { Write-Host 'SKIP Cursor not on okr-jira'; exit 0 }
Clear-CursorProcessCache; $script:LaunchCimCallCount = 0
$sw2 = [Diagnostics.Stopwatch]::StartNew()
$null = Launch-RemoteEditor -EditorCmd 'cursor' -Alias $alias -RemotePath $path -KnownOnFolder
$sw2.Stop()
Write-Host "skip_path ms=$($sw2.ElapsedMilliseconds) cim=$($script:LaunchCimCallCount)"
if ($sw2.ElapsedMilliseconds -ge 1500) { exit 1 }
exit 0
