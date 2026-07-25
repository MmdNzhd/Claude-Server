# test-folder-uri-equals-arg-live.ps1 - LIVE: proves Get-RemoteEditorLaunchStrategies emits the
# remote workspace URI in the filter-safe "--folder-uri=<uri>" combined form, never as a bare
# standalone argv token "<uri>" after a separate "--folder-uri" flag.
#
# Root cause (Cursor 3.13.x, confirmed via connect log + upstream docs): on Windows,
# Electron/Chromium's security layer drops standalone command-line arguments that contain "://"
# (they look like a URL). So `cursor --new-window --folder-uri vscode-remote://...` has its URI
# silently filtered when the invocation is handed off to an ALREADY-RUNNING Cursor instance -
# producing the "works when Cursor is closed, opens no 2nd window when Cursor is already open"
# symptom. Cold start happened to still work, so the bug only showed when opening a 2nd project.
# Refs: microsoft/vscode #209072 (folder-uri only works as last arg / no --wait), #308150
# (combine URI flags with '=' to survive Chromium argv filtering), Cursor forum #153009.
# The fix: pass "--folder-uri=$Uri" as a single token so it is a "--"-prefixed flag, not a bare URL.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== folder-uri combined "=" argv form (LIVE) ===' -ForegroundColor Cyan

$editorLaunchFile = Get-ClientFile 'editor-launch.ps1'
# Dot-source the real production file (function-definitions only at load time - no side effects)
# so the REAL Get-RemoteEditorLaunchStrategies + its helpers run exactly as shipped.
. $editorLaunchFile
Assert ((Get-Command Get-RemoteEditorLaunchStrategies -ErrorAction SilentlyContinue) -ne $null) 'Get-RemoteEditorLaunchStrategies is defined by editor-launch.ps1'

$alias = 'claude-server'
$remotePath = '/home/smart/mounts/review'
$uri = Get-RemoteFolderUri -Alias $alias -RemotePath $remotePath
Assert ($uri -match '://') "test URI actually contains '://' (the token Chromium would filter): $uri"

foreach ($nw in @($true, $false)) {
    foreach ($editor in @('cursor', 'code')) {
        $strategies = @(Get-RemoteEditorLaunchStrategies -EditorCmd $editor -Alias $alias -RemotePath $remotePath -Uri $uri -NewWindow:$nw)
        $folderStrats = @($strategies | Where-Object { $_.Name -like 'folder-uri*' })
        Assert ($folderStrats.Count -ge 1) "editor=$editor NewWindow=$nw has >=1 folder-uri strategy"
        foreach ($s in $folderStrats) {
            $sArgs = @($s.Args)
            # 1) The combined token must be present verbatim.
            $hasCombined = @($sArgs | Where-Object { $_ -eq "--folder-uri=$uri" }).Count -ge 1
            Assert $hasCombined "editor=$editor NewWindow=$nw strategy='$($s.Name)' passes combined '--folder-uri=$uri'"
            # 2) The URI must NOT appear as its own standalone argv element (the filtered form).
            $bareUri = @($sArgs | Where-Object { $_ -eq $uri }).Count
            Assert ($bareUri -eq 0) "editor=$editor NewWindow=$nw strategy='$($s.Name)' does NOT pass the URI as a bare standalone token"
            # 3) There must be no lone '--folder-uri' flag (value split off into the next element).
            $loneFlag = @($sArgs | Where-Object { $_ -eq '--folder-uri' }).Count
            Assert ($loneFlag -eq 0) "editor=$editor NewWindow=$nw strategy='$($s.Name)' has no lone '--folder-uri' flag"
        }
        # --remote fallback must remain (Cursor-recommended workaround for warm instances).
        $remoteStrats = @($strategies | Where-Object { $_.Name -like 'remote*' })
        Assert ($remoteStrats.Count -ge 1) "editor=$editor NewWindow=$nw retains a --remote fallback strategy"
    }
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'ALL PASS: remote workspace URI is passed as --folder-uri=<uri>; the standalone "://" token that Windows Electron/Chromium silently filters is never emitted, so the 2nd-window handoff to an already-running Cursor works.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
