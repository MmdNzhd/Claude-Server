#Requires -Version 5.1
# test-versioned-layout.ps1 - Claude-Connect\{ver}\src + EXE + prune-3 + fast-path contracts
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== Versioned Claude-Connect layout ===' -ForegroundColor Cyan

$launch = Get-Content (Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1') -Raw
$worker = Get-Content (Join-Path $script:RepoRoot 'publish\_setup-worker-body.ps1') -Raw
$upd = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw

Assert ($launch -match 'function Test-VersionSrcComplete') 'setup-launch has fast-path complete check'
Assert ($launch -match 'function Resolve-VersionedTree') 'setup-launch builds versioned tree'
Assert ($launch -match 'Claude-Connect') 'setup-launch uses Claude-Connect root name'
Assert ($launch -match "Join-Path \$verDir 'src'|SrcDir") 'setup-launch uses src under version dir'
Assert ($launch -match 'function Prune-OldVersionDirs') 'setup-launch prunes old versions'
Assert ($launch -match 'Keep = 3') 'setup-launch keeps 3 versions'
Assert ($launch -match 'setup fast_path') 'setup-launch logs fast_path'
Assert ($launch -match 'fast_path direct_boot') 'setup-launch boots UI directly on fast path (no worker/network)'
Assert ($launch -match 'Write-ConnectInstantLauncher') 'setup-launch writes instant launcher'
Assert ($launch -match 'Claude-Connect\.vbs') 'setup-launch writes Claude-Connect.vbs (no orphan cmd console)'
Assert ($launch -match 'Claude-Connect\.cmd') 'setup-launch still writes Claude-Connect.cmd trampoline'
Assert ($launch -match 'Move-LaunchExeIntoVerDir') 'setup-launch moves EXE into version dir'
Assert ($launch -notmatch 'SHOW_INSTALL_NOTICE = ''1''' -and ($launch -match 'Remove-Item Env:CLAUDE_CONNECT_SHOW_INSTALL_NOTICE' -or $launch -match 'fast_path direct_boot')) 'setup-launch has no install confirm notice'
Assert ($launch -notmatch 'SHOW_INSTALL_NOTICE = ''1''') 'setup-launch does not enable install notice'
Assert ($worker -notmatch 'function Show-InstallNotice') 'worker has no install MessageBox helper'
Assert ($worker -notmatch 'opened in this folder') 'worker has no relocate confirm dialog'
Assert ($worker -notmatch 'Next time, open Claude-Connect-') 'worker does not ask where to reopen'
Assert ($worker -match 'Stop-OldConnectUiBestEffort') 'worker closes old UI on relocate'
Assert ($upd -match 'function Get-ConnectVersionedLayout') 'update detects versioned layout'
Assert ($upd -match 'function Invoke-PruneConnectVersionDirs') 'update prunes version dirs'
Assert ($upd -match 'function ConvertTo-ConnectVersionedLayout') 'update migrates flat layout'
Assert ($upd -match 'versioned_apply ok') 'update applies into new version folder'
Assert ($upd -match 'Keep = 3') 'update prune keep=3'

# Live prune logic (1,5,12 + add 15 => keep 5,12,15)
$root = Join-Path $env:TEMP ("cc-ver-layout-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    foreach ($v in @('20260101.1', '20260101.5', '20260101.12')) {
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $root $v)
        Set-Content (Join-Path (Join-Path $root $v) 'marker.txt') -Value $v
    }
    # Extract + run prune function from setup-launch
    $fn = Get-FunctionSource -Content $launch -Name 'Prune-OldVersionDirs'
    Assert ($null -ne $fn) 'extracted Prune-OldVersionDirs'
    Invoke-Expression 'function Log([string]$m) {}'
    Invoke-Expression $fn
    # Simulate adding 15 then prune
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $root '20260101.15')
    Prune-OldVersionDirs -Root $root -Keep 3
    $left = @(Get-ChildItem $root -Directory | ForEach-Object { $_.Name } | Sort-Object)
    Assert ($left -contains '20260101.5') 'prune kept .5'
    Assert ($left -contains '20260101.12') 'prune kept .12'
    Assert ($left -contains '20260101.15') 'prune kept .15'
    Assert ($left -notcontains '20260101.1') 'prune removed oldest .1'
    Assert ($left.Count -eq 3) 'prune left exactly 3 dirs'

    # Fast-path complete check
    $fn2 = Get-FunctionSource -Content $launch -Name 'Test-VersionSrcComplete'
    Invoke-Expression $fn2
    $src = Join-Path $root 'src-test'
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    Assert (-not (Test-VersionSrcComplete -SrcDir $src -Version '20260101.15')) 'incomplete src => false'
    foreach ($n in @('connect.bat', 'connect.ps1', 'connect-boot.ps1', 'connect-update.ps1')) {
        Set-Content (Join-Path $src $n) -Value 'x'
    }
    Set-Content (Join-Path $src 'connect-version.txt') -Value '20260101.15' -NoNewline
    Assert (Test-VersionSrcComplete -SrcDir $src -Version '20260101.15') 'complete src => true'
    Assert (-not (Test-VersionSrcComplete -SrcDir $src -Version '20260101.99')) 'wrong version => false'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
