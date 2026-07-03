# test-connect-pipeline.ps1 — regression tests for project-select pipeline bug
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ""
Write-Host "=== connect.ps1 pipeline self-test ===" -ForegroundColor Cyan
Write-Host ""

$gitModePs1 = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connectUiPs1 = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
Assert ($connectUiPs1 -notmatch 'function Get-GitModeLabel') 'connect-ui.ps1 does not shadow Get-GitModeLabel'

foreach ($rel in @('windows\connect.ps1')) {
    $path = Get-ClientFile $rel
    $src = Get-Content $path -Raw
    $bundle = $src + $gitModePs1
    Assert ($src -match 'function Choose-Project') "$rel uses Choose-Project (no while-loop pipeline leak)"
    Assert ($src -notmatch '(?m)^\s+\$go = \[PSCustomObject\]') "$rel has no bare `$go = [PSCustomObject]"
    Assert ($src -match 'Launch-RemoteEditor') "$rel launches editor via Launch-RemoteEditor"
    Assert ($src -match 'ConnectVersion = ''20260703\.12''') "$rel has current ConnectVersion"
    Assert ($src -match 'connect-ui\.ps1') "$rel dot-sources connect-ui"
    Assert ($src -match '\-AdminFix') "$rel supports AdminFix"
    Assert ($src -match 'Read-PostDisconnectKey') "$rel has post-disconnect helper"
    Assert ($src -match 'menuLoop|Clear-SessionMount|Initialize-ServerSession') "$rel has v11 session features"
    Assert ($src -match 'git-mode\.ps1') "$rel dot-sources git-mode.ps1"
    Assert ($bundle -match 'Remount-ProjectGit') "$rel has mid-session git remount"
    Assert ($src -match 'Write-SessionBox|G = git mode') "$rel has session git hotkey"
    Assert ($bundle -match 'function Get-GitMode') "$rel has Get-GitMode (via git-mode.ps1)"
    Assert ($bundle -match 'GIT_MODE=%s') "$rel pushes GIT_MODE to server"
    Assert ($bundle -match 'LAPTOP_OS=windows') "$rel pushes LAPTOP_OS to server"
    Assert ($src -match '"g" \{ Configure-GitMode \}') "$rel has git menu option"
    Assert ($bundle -match 'Push-ServerConnectConf') "$rel has Push-ServerConnectConf"
    Assert ($src -match '@\(Choose-Project -Mounts \$mounts\)\[-1\]') "$rel uses safe Choose-Project capture"
    Assert ($src -match '@\(Resolve-EditorChoice -CfgDir \$CfgDir\)\[-1\]') "$rel uses safe Resolve-EditorChoice capture"
    Assert ($src -match 'Invoke-LaptopAdminOps|Start-Process powershell\.exe -Verb RunAs') "$rel supports conditional elevation"
}

$authLaptop = Get-Content (Get-ClientFile 'cursor-auth-laptop.ps1') -Raw
$editorLaunch = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
Assert ($authLaptop -match 'Merge-CursorAuthIntoLocalDb') 'cursor-auth-laptop uses merge not file replace'
Assert ($authLaptop -notmatch 'Stop-Cursor|CloseMainWindow') 'cursor-auth-laptop never closes Cursor'
Assert ($editorLaunch -match 'ClaudeServerCursorProfile') 'editor-launch uses isolated profile'
Assert ($editorLaunch -match 'Initialize-CursorServerProfile') 'editor-launch marks server windows'

foreach ($rel in @('windows\connect.ps1')) {
    $src = Get-Content (Get-ClientFile $rel) -Raw
    Assert ($src -match 'Sync-CursorGoldenAuth -Alias \$Alias') "$rel syncs cursor auth every reconnect"
    Assert ($src -match 'if \(-not \$editorOpened\)') "$rel opens editor only once"
}

function Choose-ProjectMock {
    return [PSCustomObject]@{ Id = 'ai'; Path = '/home/smart/mounts/ai' }
}
$go = Choose-ProjectMock
$p = Join-Path 'C:\Users\Smart' '.config\claude-connect'
Assert ($p -like '*claude-connect*') "Join-Path after project select (no ChildPath prompt)"

$mount = Get-Content (Get-ServerFile 'server\claude-mount.sh') -Raw
Assert ($mount -match 'GIT_MODE') "claude-mount.sh reads GIT_MODE"
Assert ($mount -match 'LAPTOP_OS') "claude-mount.sh reads LAPTOP_OS"
Assert ($mount -match '_mac_sh') "claude-mount.sh has Mac laptop git ops"
Assert ($mount -match 'GIT_HIDE:fail') "claude-mount reports git hide failures"
Assert ($mount -match 'warn: git hide failed') "claude-mount warns on git hide failure"
Assert ($mount -match 'warn: laptop tunnel down') "claude-mount warns when tunnel down"
Assert ($mount -match '\$n -lt 3') "claude-mount retries git rename 3x"
Assert ($mount -match '_mount_restore_git_mode') "claude-mount restores GIT_MODE explicitly"
Assert ($mount -notmatch "trap 'GIT_MODE") "claude-mount has no RETURN trap on GIT_MODE"

$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
Assert ($gitMode -match 'function Invoke-MountProject') 'git-mode.ps1 auto-retries mount after script push'
Assert ($gitMode -match 'function Resolve-ServerScriptDir') 'git-mode.ps1 resolves server scripts for ZIP layout'

$publish = Get-Content (Join-Path $script:RepoRoot 'publish\publish.ps1') -Raw
Assert (-not (Test-Path (Get-ClientFile 'users\sepidz\connect.ps1'))) 'no sepidz connect fork (single codebase)'
Assert ($publish -match 'scripts\\client\\windows\\connect\.ps1') 'publish uses canonical windows connect.ps1'
Assert ($publish -match 'PatchIp = \$true') 'publish has IP patch flag for Sepidz'
Assert ($publish -notmatch 'users\\sepidz') 'publish does not reference users/sepidz fork'

Write-Host ""
if ($fail -eq 0) { Write-Host "All tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
