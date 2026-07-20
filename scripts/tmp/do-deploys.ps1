$ErrorActionPreference='Stop'
$root = (Resolve-Path '.').Path
$pack = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717'
$sepid = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'

Write-Host '=== markers check ==='
foreach ($p in @(
  (Join-Path $pack 'windows\git-mode.ps1'),
  (Join-Path $sepid 'windows\git-mode.ps1')
)) {
  $ok = @(
    (Select-String -Path $p -Pattern 'nc -w 2' -Quiet),
    (Select-String -Path $p -Pattern 'banner_miss_tcp_open' -Quiet),
    (Select-String -Path $p -Pattern 'Reattach BEFORE' -Quiet)
  )
  Write-Host ("$p => " + ($ok -join ','))
}

Write-Host ''
Write-Host '=== SMART deploy ===' -ForegroundColor Cyan
& (Join-Path $root 'publish\deploy-client-bundles.ps1') `
  -ProjectRoot $root `
  -SmartClientRoot $pack `
  -DeploySmart `
  -DeploySepidz:$false
Write-Host "SMART_EXIT=$LASTEXITCODE"

Write-Host ''
Write-Host '=== SEPIDZ deploy ===' -ForegroundColor Cyan
& (Join-Path $root 'publish\deploy-client-bundles.ps1') `
  -ProjectRoot $root `
  -SepidClientRoot $sepid `
  -DeploySmart:$false `
  -DeploySepidz
Write-Host "SEPIDZ_EXIT=$LASTEXITCODE"

Write-Host ''
Write-Host '=== remote versions ==='
foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  $v = (& ssh -o BatchMode=yes -o ConnectTimeout=12 $t "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null")
  Write-Host "$t => [$($v.Trim())]"
}

# marker on remote bundle
foreach ($pair in @(
  @{t='smart@192.168.210.240'; l='Smart'},
  @{t='sepidz@192.168.250.70'; l='Sepidz'}
)) {
  $m = (& ssh -o BatchMode=yes -o ConnectTimeout=12 $pair.t "grep -c 'banner_miss_tcp_open' /usr/local/share/claude-client/git-mode.ps1 2>/dev/null; grep -c 'tunnelSyncOk' /usr/local/share/claude-client/connect.ps1 2>/dev/null; grep -c 'tunnelEffectivelyUp' /usr/local/share/claude-client/connect-diagnostic.ps1 2>/dev/null")
  Write-Host ("$($pair.l) markers(banner,sync,diag)=" + (($m -join ' ').Trim()))
}
