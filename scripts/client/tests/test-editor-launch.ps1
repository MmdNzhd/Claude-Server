# test-editor-launch.ps1 - quick checks for editor CLI on PATH
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

. (Get-ClientFile 'editor-launch.ps1')

Write-Host ""
Write-Host "=== Editor launch self-test ===" -ForegroundColor Cyan
Write-Host ""

Assert ([bool](Get-Command code -ErrorAction SilentlyContinue)) "code on PATH"
Assert (Get-Command Launch-RemoteEditor -ErrorAction SilentlyContinue) "Launch-RemoteEditor defined"
Assert (Get-Command Get-RemoteEditorLaunchStrategies -ErrorAction SilentlyContinue) "Get-RemoteEditorLaunchStrategies defined"
Assert (Get-Command Write-EditorLaunchSnapshot -ErrorAction SilentlyContinue) "Write-EditorLaunchSnapshot defined"
if (Get-Command cursor -ErrorAction SilentlyContinue) {
    Assert $true "cursor on PATH"
} else {
    Write-Host "  SKIP  cursor not installed" -ForegroundColor DarkGray
}

Write-Host ""
if ($fail -eq 0) { Write-Host "All tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
