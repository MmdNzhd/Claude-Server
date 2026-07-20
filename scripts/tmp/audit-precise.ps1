Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fail = 0
function Pass($m) { Write-Host "  OK  $m" -ForegroundColor Green }
function Fail($m) { Write-Host "  FAIL $m" -ForegroundColor Red; $script:fail++ }
function Info($m) { Write-Host "      $m" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "=== Precise deploy audit ===" -ForegroundColor White

# --- repo / publish files ---
Write-Host "`n[1] Publish + deploy files" -ForegroundColor Cyan
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach ($rel in @(
    'publish\publish.ps1',
    'publish\deploy-client-bundles.ps1',
    'publish\Get-DeployCredentials.ps1',
    'publish\finish-sepidz-deploy.ps1',
    'publish\finish-sepidz-deploy.bat',
    'scripts\server\commands\install-client-bundle.sh'
)) {
    if (Test-Path (Join-Path $root $rel)) { Pass $rel } else { Fail "missing $rel" }
}
if (Test-Path (Join-Path $root 'publish\sepidz-deploy.local.ps1')) { Pass 'sepidz-deploy.local.ps1 (local credentials)' } else { Fail 'missing sepidz-deploy.local.ps1 on laptop' }

$pub = Get-Content (Join-Path $root 'publish\publish.ps1') -Raw
if ($pub -match 'SkipServerDeploy' -and $pub -match 'deploy-client-bundles') { Pass 'publish.ps1 hooks deploy after ZIP' } else { Fail 'publish.ps1 deploy hook' }

$dep = Get-Content (Join-Path $root 'publish\deploy-client-bundles.ps1') -Raw
if ($dep -match 'sepidz@192\.168\.250\.70') { Pass 'deploy default Sepidz target = sepidz@192.168.250.70' } else { Fail 'deploy Sepidz target' }
if ($dep -match '192\.168\.210\.240') { Pass 'deploy Smart target = smart@192.168.210.240' } else { Fail 'deploy Smart target' }
if ($dep -match 'Get-SepidzSudoPassword') { Pass 'deploy reads Sepidz sudo password' } else { Fail 'deploy password hook' }
if ($dep -match '_extract_zip') { Fail 'deploy references _extract_zip in wrong file' } # install script has this

$install = Get-Content (Join-Path $root 'scripts\server\commands\install-client-bundle.sh') -Raw
if ($install -match '_extract_zip') { Pass 'install-client-bundle has python3 zip fallback' } else { Fail 'install zip fallback' }

# --- desktop publish folders ---
Write-Host "`n[2] Desktop publish packages" -ForegroundColor Cyan
$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$smartDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-client-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
$sepidDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if ($smartDir) {
    $sv = (Get-Content (Join-Path $smartDir.FullName 'windows\connect-version.txt') -Raw).Trim()
    $sip = [regex]::Matches((Get-Content (Join-Path $smartDir.FullName 'windows\connect.ps1') -Raw), '192\.168\.\d+\.\d+').Count
    Pass "Smart ZIP folder $($smartDir.Name) v$sv Smart-IP-hits=$sip"
    if ($sip -ne 1) { Fail 'Smart connect.ps1 should have exactly 1 IP' }
} else { Fail 'no Smart publish folder on Desktop' }
if ($sepidDir) {
    $cc = Join-Path $sepidDir.FullName 'claude-code'
    $sv = (Get-Content (Join-Path $cc 'windows\connect-version.txt') -Raw).Trim()
    $hasSep = (Get-Content (Join-Path $cc 'windows\connect.ps1') -Raw) -match '192\.168\.250\.70'
    $hasSmart = (Get-Content (Join-Path $cc 'windows\connect.ps1') -Raw) -match '192\.168\.210\.240'
    Pass "Sepidz ZIP folder $($sepidDir.Name) v$sv"
    if ($hasSep -and -not $hasSmart) { Pass 'Sepidz connect.ps1 IP patched only to 250.70' } else { Fail 'Sepidz IP patch' }
    if ($sv -eq (Get-Content (Join-Path $smartDir.FullName 'windows\connect-version.txt') -Raw).Trim()) { Pass 'Smart/Sepidz same connect version' } else { Fail 'version mismatch Smart vs Sepidz publish' }
} else { Fail 'no Sepidz publish folder on Desktop' }

# --- server bundles ---
Write-Host "`n[3] Server auto-update bundles" -ForegroundColor Cyan
function Audit-Server($label, $target, $expectIp, $expectVer) {
    $f = Join-Path $env:TEMP "precise-$label.txt"
    $remote = @"
set -e
B=/usr/local/share/claude-client
test -d `$B || { echo STATUS=MISSING; exit 0; }
ver=`$(tr -d '\r\n' < `$B/connect-version.txt)
ip=`$(grep -o '192.168.[0-9.]*' `$B/connect.ps1 | head -1)
macip=`$(grep -o '192.168.[0-9.]*' `$B/mac/connect.sh | head -1)
bash -n `$B/mac/claude-mount.sh && m=OK || m=FAIL
test -f `$B/mac/claude-mount.sh && cm=1 || cm=0
test -f `$B/connect-update.ps1 && cu=1 || cu=0
test -f `$B/manifest.txt && mf=`$(wc -l < `$B/manifest.txt) || mf=0
test -f `$B/server/claude-mount.sh && sm=1 || sm=0
echo STATUS=OK
echo version=`$ver
echo ip=`$ip
echo macip=`$macip
echo mount=`$m
echo mac_mount=`$cm
echo connect_update=`$cu
echo manifest_files=`$mf
echo server_mount=`$sm
"@
    Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10',$target,"bash -lc '$remote'") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $f -RedirectStandardError (Join-Path $env:TEMP "precise-$label.err") | Out-Null
    $lines = @(Get-Content $f -ErrorAction SilentlyContinue)
    $h = @{}
    foreach ($line in $lines) { if ($line -match '^([^=]+)=(.*)$') { $h[$Matches[1]] = $Matches[2] } }
    Write-Host "`n  $label ($target)" -ForegroundColor White
    if ($h.STATUS -ne 'OK') { Fail "$label bundle missing"; return }
    Info "version=$($h.version) ip=$($h.ip) macip=$($h.macip) mount=$($h.mount) manifest=$($h.manifest_files) files"
    if ($h.version -eq $expectVer) { Pass "$label version $expectVer" } else { Fail "$label version expected $expectVer got $($h.version)" }
    if ($h.ip -eq $expectIp) { Pass "$label connect.ps1 IP $expectIp" } else { Fail "$label connect.ps1 IP expected $expectIp got $($h.ip)" }
    if ($h.macip -eq $expectIp) { Pass "$label mac/connect.sh IP $expectIp" } else { Fail "$label mac/connect.sh IP expected $expectIp got $($h.macip)" }
    if ($h.mount -eq 'OK') { Pass "$label claude-mount.sh syntax" } else { Fail "$label claude-mount syntax" }
    if ($h.connect_update -eq '1') { Pass "$label has connect-update.ps1" } else { Fail "$label missing connect-update.ps1" }
    if ([int]$h.manifest_files -gt 15) { Pass "$label manifest ($($h.manifest_files) files)" } else { Fail "$label manifest too small ($($h.manifest_files))" }
    if ($h.server_mount -eq '1') { Pass "$label has server/claude-mount.sh" } else { Fail "$label missing server/claude-mount.sh" }
}
$expectVer = if ($smartDir) { (Get-Content (Join-Path $smartDir.FullName 'windows\connect-version.txt') -Raw).Trim() } else { '20260715.17' }
Audit-Server 'Smart' 'smart@192.168.210.240' '192.168.210.240' $expectVer
Audit-Server 'Sepidz' 'sepidz@192.168.250.70' '192.168.250.70' $expectVer

# --- SSH reachability ---
Write-Host "`n[4] SSH" -ForegroundColor Cyan
foreach ($pair in @(@('Smart','smart@192.168.210.240'), @('Sepidz','sepidz@192.168.250.70'))) {
    $f = Join-Path $env:TEMP "ssh-$($pair[0]).txt"
    Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5',$pair[1],'echo OK') -NoNewWindow -Wait -PassThru -RedirectStandardOutput $f | Out-Null
    $o = Get-Content $f -Raw -ErrorAction SilentlyContinue
    if ($o -match 'OK') { Pass "SSH $($pair[0]) $($pair[1])" } else { Fail "SSH $($pair[0])" }
}

# --- credentials file (no secret print) ---
Write-Host "`n[5] Local credentials (no secrets printed)" -ForegroundColor Cyan
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')
$u = Get-SepidzSshUser
$t = Get-SepidzServerTarget
$pw = Get-SepidzSudoPassword
if ($u -eq 'sepidz') { Pass "SepidzSshUser=$u" } else { Fail "SepidzSshUser expected sepidz got $u" }
if ($t -eq 'sepidz@192.168.250.70') { Pass "SepidzServerTarget=$t" } else { Fail "SepidzServerTarget=$t" }
if ($pw -and $pw.Length -gt 0) { Pass "SepidzSudoPassword set ($($pw.Length) chars)" } else { Fail 'SepidzSudoPassword not set' }

Write-Host ""
if ($fail -eq 0) { Write-Host "All precise checks passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail check(s) FAILED." -ForegroundColor Red; exit 1
