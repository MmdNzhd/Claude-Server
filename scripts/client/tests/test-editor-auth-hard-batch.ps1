# test-editor-auth-hard-batch.ps1 - deep RED/GREEN contracts for editor launch + auth wiring.
# Callers: manual / CI on Windows laptop (NOT wired into run-all.ps1 by design).
#
# Locks live regressions from 2026-07-25..27:
#   - isolated ClaudeServerCursorProfile dirs (Smart vs Sepidz; personal Cursor untouched)
#   - Path.Combine for editor.conf (Join-Path pipeline ChildPath prompt)
#   - combined --folder-uri=<uri> argv (Windows Electron filters bare vscode-remote:// tokens)
#   - SESSION trust path after successful launch (no immediate re-probe / double relaunch)
#   - Opening fail clears sticky EditorSeenOpen when window not proven
#   - Recovery skips press-O nag when already on folder
#   - AuthRelaunch preserves open profile windows when already on target folder
#   - Auth relaunch never soft-stops profile tree; auth merge never kills personal Cursor
#   - Template-anchored window-title -> project match (site-tag collision guard)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

$elPath = Get-ClientFile 'editor-launch.ps1'
$winPath = Get-ClientFile 'windows\connect.ps1'
$authPath = Get-ClientFile 'cursor-auth-laptop.ps1'
$elSrc = Get-Content -LiteralPath $elPath -Raw
$winSrc = Get-Content -LiteralPath $winPath -Raw
$authSrc = Get-Content -LiteralPath $authPath -Raw

. $elPath

Write-Host ''
Write-Host '=== Editor + auth hard batch (19 asserts) ===' -ForegroundColor Cyan
Write-Host ''

# 1) Isolated server profile dirs differ by site (Smart vs Sepidz)
$script:CursorProfileSite = 'Smart'
$smartDir = Get-CursorRemoteProfileDir
$script:CursorProfileSite = 'Sepidz'
$sepidzDir = Get-CursorRemoteProfileDir
Assert (
    ($smartDir -eq (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart')) -and
    ($sepidzDir -eq (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Sepidz')) -and
    ($smartDir -ne $sepidzDir)
) 'Get-CursorRemoteProfileDir isolates Smart vs Sepidz under LOCALAPPDATA'

# 2) Personal Cursor profile is never the server profile target
Assert ($elSrc -match 'Personal Cursor \(%APPDATA%\\Cursor\) is never touched') `
    'Get-CursorRemoteProfileDir documents personal Cursor is never touched'

# 2b) One-time legacy profile migrate ships (history restore after Smart/Sepidz split)
Assert (
    ($elSrc -match 'function Ensure-CursorRemoteProfileMigrated') -and
    ($elSrc -match 'ClaudeServerCursorProfile\.bak-keep-') -and
    ($elSrc -match '\.claude-connect-profile-migrated')
) 'Ensure-CursorRemoteProfileMigrated one-time legacy->site profile migrate present'

# 3) editor.conf uses Path.Combine (Join-Path pipeline ChildPath bug)
Assert (
    ($elSrc -match '\[System\.IO\.Path\]::Combine\(\$CfgDir,\s*''editor\.conf''\)') -and
    ($elSrc -match 'Join-Path binds pipeline input and causes ChildPath prompt')
) 'Resolve-EditorChoice uses Path.Combine for editor.conf with Join-Path hazard comment'

# 4) connect.ps1 persists editor choice via Path.Combine (not Join-Path)
Assert (
    ($winSrc -match '\[System\.IO\.Path\]::Combine\(\$CfgDir,\s*''editor\.conf''\)') -and
    ($winSrc -notmatch 'Join-Path\s+\$CfgDir\s+''editor\.conf''')
) 'connect.ps1 writes editor.conf via Path.Combine only'

# 5) folder-uri argv uses combined --folder-uri=<uri> (never lone flag or bare URI token)
$alias = 'claude-server'
$path = '/home/smart/mounts/hard-batch'
$uri = Get-RemoteFolderUri -Alias $alias -RemotePath $path
$folderStrats = @(Get-RemoteEditorLaunchStrategies -EditorCmd 'cursor' -Alias $alias -RemotePath $path -Uri $uri -NewWindow |
    Where-Object { $_.Name -like 'folder-uri*' })
$folderUriOk = ($folderStrats.Count -ge 1)
foreach ($s in $folderStrats) {
    if (@($s.Args | Where-Object { $_ -eq "--folder-uri=$uri" }).Count -lt 1) { $folderUriOk = $false }
    if (@($s.Args | Where-Object { $_ -eq '--folder-uri' }).Count -gt 0) { $folderUriOk = $false }
}
Assert $folderUriOk 'folder-uri strategies pass combined --folder-uri=<uri> with no lone flag'

# 6) Trust path after launch: no immediate on_folder re-probe (double relaunch guard)
$trustBlock = [regex]::Match(
    $winSrc,
    '(?ms)if\s*\(\s*\$didLaunch\s*-and\s*\$launchOk\s*\)\s*\{.*?Write-ConnectLog\s+''SESSION: trusting launch result[^'']*''.*?\}'
).Value
Assert (
    ($trustBlock.Length -gt 40) -and
    ($trustBlock -match '\$onFolderNow\s*=\s*\$true') -and
    ($trustBlock -notmatch 'Test-RemoteEditorOnCorrectFolder')
) 'didLaunch+launchOk trust path sets onFolderNow without re-probe'

# 7) Opening fail clears sticky editor flags when window not proven
$openingClear = [regex]::Match(
    $winSrc,
    '(?ms)if\s*\(\s*-not\s*\$launchOk\s*\)\s*\{.*?if\s*\(\s*-not\s*\$windowOpenInit\s*\)\s*\{.*?EDITOR_SEEN_CLEAR reason=opening_step_fail.*?\}'
).Value
Assert (
    ($winSrc -match 'EDITOR_SEEN_CLEAR reason=opening_step_fail') -and
    ($openingClear.Length -gt 30) -and
    ($openingClear -match '\$script:EditorSeenOpen\s*=\s*\$false') -and
    ($openingClear -match '\$script:EditorOpened\s*=\s*\$false')
) 'opening_step_fail clears EditorSeenOpen/EditorOpened when window not proven'

# 8) Recovery skips press-O warn when already on folder
Assert (
    ($winSrc -match 'skip_press_o_warn reason=already_on_folder') -and
    ($winSrc -match '(?ms)PostTunnelRecovery\s*-and\s*-not\s*\$onCorrectFolder[\s\S]{0,220}press O')
) 'recovery press-O warn skipped when already_on_folder; only nags when not on folder'

# 9) AuthRelaunch skip preserve when profile open on target folder
Assert (
    ($winSrc -match '\$skipForPreserve\s*=\s*\(\$authRelaunch\s*-and\s*\$profileAlreadyOpen\s*-and\s*\$onCorrectFolder\)') -and
    ($winSrc -match 'skip_auth_relaunch reason=profile_windows_open_preserve_after_tunnel_recovery')
) 'AuthRelaunch skipForPreserve when profile windows open on correct folder'

# 10) Auth merge never closes/kills Cursor (personal or profile)
Assert ($authSrc -notmatch 'Stop-Cursor|CloseMainWindow|Stop-Process') `
    'cursor-auth-laptop never Stop-Process/CloseMainWindow'

# 11) AuthRelaunch never soft-stops ClaudeServerCursorProfile tree
Assert ($elSrc -match 'LAUNCH_KILL_SKIP: reason=auth_relaunch_never_kill') `
    'Launch-RemoteEditor auth_relaunch_never_kill (no profile tree soft-stop)'

# 12) Site-tag collision: project "smart" must not match bare site-tagged window
$tag = 'Claude Server Smart'
Assert (-not (Test-CursorWindowTitleMatchesProject -Title "[$tag]" -RootName 'smart' -TitleTag $tag)) `
    'Test-CursorWindowTitleMatchesProject rejects site-tag collision for project smart'

# 13) Window title template keeps VS Code ${...} literals (not PowerShell-expanded empty)
$tpl = Get-CursorServerWindowTitleTemplate -TitleTag $tag
Assert (
    ($tpl -match '\$\{rootName\}') -and ($tpl -match '\$\{dirty\}') -and ($tpl -match '\[Claude Server Smart\]')
) 'Get-CursorServerWindowTitleTemplate preserves ${rootName} and site tag literals'

# 14) on_folder detection requires title-matched VISIBLE window (not cmdline+any visible)
Assert (
    ($elSrc -match 'function Test-CursorVisibleWindowMatchesProject') -and
    ($elSrc -match 'Test-CursorVisibleWindowMatchesProject -ProcessId') -and
    ($elSrc -notmatch 'if \(\$visibleWins\.Count -gt 0\) \{ return \$true \}')
) 'on_folder requires Test-CursorVisibleWindowMatchesProject (no cmdline+any-visible shortcut)'

# 15) Confirm-RemoteEditorLaunchVisible is project-scoped (no any-MainWindowHandle return)
$confirmFn = Get-FunctionSource -Content $elSrc -Name 'Confirm-RemoteEditorLaunchVisible'
Assert (
    ($confirmFn -match 'Test-RemoteEditorOnCorrectFolder') -and
    ($confirmFn -match 'Project-scoped only') -and
    ($confirmFn -notmatch 'if \(\$wp\.MainWindowHandle -ne \[IntPtr\]::Zero\) \{ return \$true \}')
) 'Confirm-RemoteEditorLaunchVisible is project-scoped only'

# 16) Preparing-tunnel: skip sidecar thrash when tunnel has no proxy legs
$gmSrc = Get-Content -LiteralPath (Get-ClientFile 'git-mode.ps1') -Raw
Assert (
    ($gmSrc -match 'skip_sidecar reason=no_tunnel_proxy_legs') -and
    ($gmSrc -match 'PROXY_FALLBACK mode=server_direct reason=no_tunnel_proxy_legs')
) 'Complete-CursorProxyAfterTunnel skips sidecar when no tunnel proxy legs'

# 17) Skip must NOT use Get-SocksProxyPort defaults / adopt_backends (always 19080) — that defeated skip (P0)
$completeFn = Get-FunctionSource -Content $gmSrc -Name 'Complete-CursorProxyAfterTunnel'
Assert (
    ($completeFn -match 'sessionHasLegs') -and
    ($completeFn -match 'SessionTunnelProxyLegs') -and
    ($completeFn -notmatch 'adopt_backends') -and
    ($completeFn -notmatch 'elseif \(Get-Command Get-SocksProxyPort')
) 'Complete skip uses session legs only (no adopt_backends / Get-SocksProxyPort fallback)'

# 18) WindowOpenWhenOnFolder is title-matched for cursor (no cmdline+any-MainWindowHandle first)
$winOpenFn = Get-FunctionSource -Content $elSrc -Name 'Test-RemoteEditorWindowOpenWhenOnFolder'
Assert (
    ($winOpenFn -match 'Project-scoped only') -and
    ($winOpenFn -match 'Test-CursorWindowTitleMatchesProject') -and
    ($winOpenFn -match 'Get-CursorMainProfileProcesses') -and
    ($winOpenFn -match "if \(\`$EditorCmd -eq 'cursor'\)")
) 'WindowOpenWhenOnFolder requires title-matched visible window for cursor'

# 19) Post-auth Ensure gated (2nd thrash after AUTH in live a8a37c2a418d)
Assert (
    ($winSrc -match 'SIDECAR_ENSURE skip reason=no_tunnel_proxy_legs') -and
    ($winSrc -match 'SessionTunnelProxyLegs -eq \$false')
) 'connect.ps1 skips post-auth Ensure-CursorProxySidecar when no tunnel proxy legs'

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All editor-auth hard-batch tests passed (19 asserts).' -ForegroundColor Green
    exit 0
}
Write-Host "$fail test(s) failed." -ForegroundColor Red
exit 1
