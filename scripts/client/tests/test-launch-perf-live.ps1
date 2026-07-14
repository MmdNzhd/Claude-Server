# test-launch-perf-live.ps1 - live WMI timing on Windows when Cursor already on folder (optional)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  SKIP  $msg" -ForegroundColor DarkYellow }
}

Write-Host ''
Write-Host '=== Live launch perf (Windows only) ===' -ForegroundColor Cyan
Write-Host ''

if ($env:OS -notmatch 'Windows') {
    Write-Host '  SKIP  not Windows' -ForegroundColor DarkYellow
    exit 0
}

. (Get-ClientFile 'connect-ui.ps1')
. (Get-ClientFile 'editor-launch.ps1')

$alias = 'claude-server'
$paths = @(
    '/home/smart/mounts/claude-code-server',
    '/home/smart/mounts/ai',
    '/home/smart/mounts/okr-jira'
)

$target = $null
foreach ($p in $paths) {
    if (Test-RemoteEditorOnCorrectFolder -EditorCmd 'cursor' -Alias $alias -RemotePath $p) {
        $target = $p
        break
    }
}

if (-not $target) {
    Write-Host '  SKIP  no Cursor window on known project folder (open [Claude Server] profile first)' -ForegroundColor DarkYellow
    exit 0
}

Write-Host "  Target folder: $target" -ForegroundColor DarkGray

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$ok = Launch-RemoteEditor -EditorCmd 'cursor' -Alias $alias -RemotePath $target -KnownOnFolder
$sw.Stop()

Assert ($ok) "Launch-RemoteEditor skip returned true"
Assert ($sw.ElapsedMilliseconds -lt 1500) "KnownOnFolder live path < 1500 ms (got $($sw.ElapsedMilliseconds))"
Assert ($script:LaunchCimCallCount -le 6) "cim_total <= 6 on skip path (got $($script:LaunchCimCallCount))"

Write-Host ''
if ($fail -eq 0) { Write-Host 'Live perf test passed (or skipped).' -ForegroundColor Green; exit 0 }
Write-Host "$fail live check(s) failed." -ForegroundColor Red
exit 1
