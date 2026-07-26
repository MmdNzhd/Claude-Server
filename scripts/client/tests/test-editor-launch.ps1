# test-editor-launch.ps1 - quick checks for editor CLI on PATH
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

$editorLaunchPath = Get-ClientFile 'editor-launch.ps1'
$src = Get-Content -LiteralPath $editorLaunchPath -Raw
. $editorLaunchPath

Write-Host ""
Write-Host "=== Editor launch self-test ===" -ForegroundColor Cyan
Write-Host ""

Assert ([bool](Get-Command code -ErrorAction SilentlyContinue)) "code on PATH"
Assert (Get-Command Launch-RemoteEditor -ErrorAction SilentlyContinue) "Launch-RemoteEditor defined"
Assert (Get-Command Get-RemoteEditorLaunchStrategies -ErrorAction SilentlyContinue) "Get-RemoteEditorLaunchStrategies defined"
Assert (Get-Command Write-EditorLaunchSnapshot -ErrorAction SilentlyContinue) "Write-EditorLaunchSnapshot defined"
$cursorCmd = Get-Command cursor -ErrorAction SilentlyContinue
if ($cursorCmd) {
    Assert ([bool]$cursorCmd.Source) "cursor on PATH ($($cursorCmd.Source))"
} else {
    Write-Host "  SKIP  cursor not installed" -ForegroundColor DarkGray
}

$startAt = $src.IndexOf('function Start-ProcessAsInteractiveUser')
$endAt = $src.IndexOf('$script:EditorCimCache', $startAt)
$launchFn = if ($startAt -ge 0 -and $endAt -gt $startAt) { $src.Substring($startAt, $endAt - $startAt) } else { '' }
Assert ($src -match 'cursor-launch-\{0\}\.log' -and $src -match "Get-Date -Format 'yyyyMMdd'") 'Cursor stdout/stderr uses a day log'
Assert ($src -match 'function Start-EditorProcessDirect') 'Start-EditorProcessDirect helper defined'
Assert ($src -match 'RedirectStandardOutput' -and $src -match 'RedirectStandardError') 'direct launch redirects stdout and stderr'
Assert (([regex]::Matches($launchFn, 'Start-EditorProcessDirect -FilePath')).Count -eq 2) 'both direct launch paths use Direct launcher'
Assert (([regex]::Matches($launchFn, 'Start-EditorProcessQuiet -FilePath')).Count -eq 0) 'interactive launch does not use Quiet launcher'
Assert ($src -notmatch 'function\s+Start-EditorProcessQuiet\b') 'Start-EditorProcessQuiet helper removed (dead SAFE_DELETE)'
Assert ($launchFn -notmatch 'Start-Process\s+-FilePath') 'interactive launch has no direct Start-Process call'
$neAt = $launchFn.IndexOf('[NonElevatedLauncher]::Start')
$taskAt = $launchFn.IndexOf('Start-ProcessViaLaunchTask')
$directAt = $launchFn.IndexOf("PROC_START: mode=elevated_direct_fallback")
Assert ($neAt -ge 0 -and $taskAt -gt $neAt -and $directAt -gt $taskAt) 'launch order is NE then LIMITED task then elevated fallback'
Assert ($launchFn -notmatch 'if\s*\(\$neStarted\)' -and $launchFn -notmatch 'skip_launch_task') 'launch task is attempted when NE Start=false'
Assert ($launchFn -match 'Start=false win32=\$winErr') 'NE Start=false logs Win32 error'
Assert ($launchFn -match '\$evidenceMsTask\s*=\s*4000') 'launch-task evidence timeout stays short'

Write-Host ""
if ($fail -eq 0) { Write-Host "All tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
