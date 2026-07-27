#Requires -Version 5.1
# test-exe-promote-dirs-contract.ps1 - EXE promote dirs: stamp/env, HashSet dedupe, UI lines, no nested-array return.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== EXE promote dirs contracts (static) ===' -ForegroundColor Cyan
Write-Host ''

$updPath = Get-ClientFile 'windows\connect-update.ps1'
$src = Get-Content -LiteralPath $updPath -Raw

Assert ($src -match 'function Get-ConnectExePromoteDirs') 'Get-ConnectExePromoteDirs defined'
Assert ($src -match 'function Test-IsConnectVersionedRootDir') 'skips Claude-Connect root when versioned'
Assert ($src -match 'function Test-IsConnectVersionedSrcDir') 'skips src\ for EXE promote'
Assert ($src -match 'do NOT drop EXEs here' -or $src -match 'never litter the root') 'documents no EXE litter at versioned root'
Assert ($src -match 'function Sync-ConnectExeBesideClient') 'Sync-ConnectExeBesideClient defined'
Assert ($src -match 'last-launch-dir\.txt') 'connect-update persists last-launch-dir.txt'
Assert ($src -match 'CLAUDE_CONNECT_LAUNCH_DIR') 'connect-update honors CLAUDE_CONNECT_LAUNCH_DIR'
Assert ($src -match 'HashSet\[string\]') 'Get-ConnectExePromoteDirs dedupes with HashSet[string]'
Assert ($src -notmatch 'return\s*,\s*\$dirs\.ToArray\(\)') 'no return ,$dirs.ToArray() nested-array bug'

$promoteFn = Get-FunctionSource -Content $src -Name 'Get-ConnectExePromoteDirs'
Assert ($promoteFn -and ($promoteFn -match 'return \$dirs')) 'Get-ConnectExePromoteDirs returns $dirs directly (not unary comma)'

$syncFn = Get-FunctionSource -Content $src -Name 'Sync-ConnectExeBesideClient'
Assert ($syncFn -and ($syncFn -match 'Get-ConnectExePromoteDirs')) 'Sync-ConnectExeBesideClient calls Get-ConnectExePromoteDirs'
Assert ($syncFn -and ($syncFn -match 'Claude-Connect-\{0\}\.exe' -or $syncFn -match 'Claude-Connect-\$\{')) 'Sync writes versioned Claude-Connect-{ver}.exe'
Assert ($syncFn -and ($syncFn -match 'foreign_verdir')) 'Sync skips Claude-Connect-NEW.exe inside OLD \{ver\} folders'

Assert ($src -match 'Sync-ConnectExeBesideClient -VersionLabel \$remoteVer') 'apply path calls Sync with remoteVer'
Assert ($src -match 'EXE ready:') 'apply path prints EXE ready lines'
Assert ($src -match 'older Claude-Connect-\*\.exe files kept') 'apply path notes older EXEs kept'
Assert ($src -match 'LastExeVersionedPaths') 'Sync surfaces written paths for UI'

$setupLaunch = Join-Path $RepoRoot 'publish\_setup-launch-body.ps1'
Assert (Test-Path -LiteralPath $setupLaunch) 'publish/_setup-launch-body.ps1 exists'
if (Test-Path -LiteralPath $setupLaunch) {
    $sl = Get-Content -LiteralPath $setupLaunch -Raw
    Assert ($sl -match 'CLAUDE_CONNECT_LAUNCH_DIR') 'SFX setup-launch stamps CLAUDE_CONNECT_LAUNCH_DIR'
    Assert ($sl -match 'CLAUDE_CONNECT_INSTALL_DIR') 'SFX setup-launch stamps CLAUDE_CONNECT_INSTALL_DIR'
    Assert (($sl -match 'Resolve-ConnectLaunchExe') -or ($sl -match 'Resolve-VersionedTree')) 'SFX setup-launch has launch / versioned resolver'
    Assert ($sl -match 'last-launch-dir\.txt') 'SFX setup-launch writes last-launch-dir.txt'
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
