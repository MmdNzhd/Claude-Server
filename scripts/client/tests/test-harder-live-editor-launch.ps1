#Requires -Version 5.1
# test-harder-live-editor-launch.ps1 - LIVE extracted editor-launch contracts (~14 asserts).
# Callers: manual / CI on Windows laptop (NOT wired into run-all.ps1 by design).
#
# Extracts Get-RemoteEditorLaunchStrategies, Get-CursorRemoteProfileDir,
# Test-CursorWindowTitleMatchesProject from editor-launch.ps1 via Get-FunctionSource +
# Invoke-Expression so >= half the asserts exercise the exact shipped function bodies.
#
# Locks:
#   - combined --folder-uri=<uri> argv (no lone flag / bare URI token)
#   - Smart vs Sepidz profile dir isolation under LOCALAPPDATA
#   - template-anchored title match rejects site-tag collision for project "smart"
#   - Path.Combine for editor.conf (Join-Path ChildPath hazard)
#   - connect.ps1 opening_step_fail / already_on_folder contracts
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== HARDER LIVE: editor-launch extracted contracts (~14 asserts) ===' -ForegroundColor Cyan
Write-Host ''

$elPath = Get-ClientFile 'editor-launch.ps1'
$winPath = Get-ClientFile 'windows\connect.ps1'
$elSrc = Get-Content -LiteralPath $elPath -Raw
$winSrc = Get-Content -LiteralPath $winPath -Raw

# Dependency chain for the three API functions under test (exact shipped bodies, isolated load).
$extractOrder = @(
    'Get-CursorRemoteProfileSite',
    'Get-CursorRemoteProfileDir',
    'Get-CursorWindowTitleTag',
    'Test-CursorWindowTitleMatchesProject',
    'Get-RemoteFolderUri',
    'Get-CodeRemoteProfileDir',
    'Write-EditorLaunchLog',
    'Get-CursorProxyLaunchArgs',
    'Get-RemoteEditorLaunchStrategies'
)
foreach ($fn in $extractOrder) {
    $chunk = Get-FunctionSource -Content $elSrc -Name $fn
    if (-not $chunk) {
        Write-Host "  FAIL  extractable via Get-FunctionSource: $fn" -ForegroundColor Red
        $Fail++
        Write-Host ''
        Write-Host "Passed: $Pass  Failed: $Fail" -ForegroundColor Red
        exit 1
    }
    Invoke-Expression $chunk
}
Assert ((Get-Command Get-RemoteEditorLaunchStrategies -ErrorAction SilentlyContinue) -ne $null) `
    'Invoke-Expression extracted Get-RemoteEditorLaunchStrategies (+ deps) into script scope'

$tag = 'Claude Server Smart'
$alias = 'claude-server'
$remotePath = '/home/smart/mounts/harder-live-editor'
$uri = Get-RemoteFolderUri -Alias $alias -RemotePath $remotePath

# --- LIVE: profile dir Smart vs Sepidz isolation -----------------------------------------------
$script:CursorProfileSite = 'Smart'
$smartDir = Get-CursorRemoteProfileDir
$script:CursorProfileSite = 'Sepidz'
$sepidzDir = Get-CursorRemoteProfileDir
$script:CursorProfileSite = $null

Assert (
    ($smartDir -eq (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart')) -and
    ($sepidzDir -eq (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Sepidz')) -and
    ($smartDir -ne $sepidzDir)
) 'LIVE Get-CursorRemoteProfileDir isolates Smart vs Sepidz under LOCALAPPDATA'

$script:CursorProfileSite = $null
$script:ServerIP = '192.168.250.70'
Assert ((Get-CursorRemoteProfileDir) -eq (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Sepidz')) `
    'LIVE Get-CursorRemoteProfileDir resolves Sepidz via ServerIP fallback'
$script:ServerIP = $null

Assert ($elSrc -match 'Personal Cursor \(%APPDATA%\\Cursor\) is never touched') `
    'Get-CursorRemoteProfileDir documents personal Cursor is never touched'

# --- LIVE: site-tag collision guard for project "smart" --------------------------------------
Assert (-not (Test-CursorWindowTitleMatchesProject -Title "[$tag]" -RootName 'smart' -TitleTag $tag)) `
    'LIVE Test-CursorWindowTitleMatchesProject rejects bare site tag for project smart'

Assert (Test-CursorWindowTitleMatchesProject -Title "[$tag] smart" -RootName 'smart' -TitleTag $tag) `
    'LIVE Test-CursorWindowTitleMatchesProject accepts anchored "[Claude Server Smart] smart"'

$aliasEsc = [regex]::Escape($alias)
Assert (-not (Test-CursorWindowTitleMatchesProject -Title "[$tag] refactoreoldclub [SSH: claude-server]" -RootName 'smart' -TitleTag $tag -AliasNeedleEscaped $aliasEsc)) `
    'LIVE Test-CursorWindowTitleMatchesProject rejects site-tag+SSH collision for project smart'

# --- LIVE: combined --folder-uri=<uri> (no lone flag, no bare URI token) ----------------------
$folderUriLiveOk = $true
foreach ($nw in @($true, $false)) {
    foreach ($editor in @('cursor', 'code')) {
        $strategies = @(Get-RemoteEditorLaunchStrategies -EditorCmd $editor -Alias $alias -RemotePath $remotePath -Uri $uri -NewWindow:$nw)
        $folderStrats = @($strategies | Where-Object { $_.Name -like 'folder-uri*' })
        if ($folderStrats.Count -lt 1) { $folderUriLiveOk = $false; continue }
        foreach ($s in $folderStrats) {
            $sArgs = @($s.Args)
            if (@($sArgs | Where-Object { $_ -eq "--folder-uri=$uri" }).Count -lt 1) { $folderUriLiveOk = $false }
            if (@($sArgs | Where-Object { $_ -eq '--folder-uri' }).Count -gt 0) { $folderUriLiveOk = $false }
            if (@($sArgs | Where-Object { $_ -eq $uri }).Count -gt 0) { $folderUriLiveOk = $false }
        }
    }
}
Assert $folderUriLiveOk 'LIVE Get-RemoteEditorLaunchStrategies emits combined --folder-uri=<uri> only (cursor+code, both NewWindow values)'

$warmStrats = @(Get-RemoteEditorLaunchStrategies -EditorCmd 'cursor' -Alias $alias -RemotePath $remotePath -Uri $uri -NewWindow -WarmHandoff)
Assert (
    ($warmStrats.Count -eq 1) -and ($warmStrats[0].Name -eq 'remote') -and
    (@($warmStrats[0].Args | Where-Object { $_ -like '--folder-uri=*' }).Count -eq 0)
) 'LIVE WarmHandoff returns remote-only strategy (no folder-uri cascade)'

# --- STATIC: Path.Combine for editor.conf ----------------------------------------------------
$resolveFn = Get-FunctionSource -Content $elSrc -Name 'Resolve-EditorChoice'
Assert (
    ($resolveFn -match '\[System\.IO\.Path\]::Combine\(\$CfgDir,\s*''editor\.conf''\)') -and
    ($resolveFn -match 'Join-Path binds pipeline input and causes ChildPath prompt')
) 'Resolve-EditorChoice uses Path.Combine for editor.conf with Join-Path hazard comment'

Assert (
    ($winSrc -match '\[System\.IO\.Path\]::Combine\(\$CfgDir,\s*''editor\.conf''\)') -and
    ($winSrc -notmatch 'Join-Path\s+\$CfgDir\s+''editor\.conf''')
) 'connect.ps1 writes editor.conf via Path.Combine only'

# --- STATIC: opening_step_fail / already_on_folder contracts in connect.ps1 -------------------
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

Assert (
    ($winSrc -match 'skip_press_o_warn reason=already_on_folder') -and
    ($winSrc -match 'EDITOR_LAUNCH auth_relaunch despite already_on_folder')
) 'connect.ps1 already_on_folder skips press-O warn and allows auth relaunch on folder'

Assert ($elSrc -match '\$folderUriArg\s*=\s*"--folder-uri=\$Uri"') `
    'Get-RemoteEditorLaunchStrategies source binds folderUriArg to combined equals form'

Write-Host ''
Write-Host "Passed: $Pass  Failed: $Fail" -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
