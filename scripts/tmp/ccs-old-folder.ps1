$ErrorActionPreference = 'Continue'
Write-Host '=== Desktop Claude-Connect ==='
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
@(
  'connect-version.txt','connect.ps1','connect-update.ps1','cursor-proxy-sidecar.ps1','git-mode.ps1','editor-launch.ps1'
) | ForEach-Object {
  $p = Join-Path $desk $_
  Write-Host ("{0} exists={1}" -f $_, (Test-Path $p))
}
if (Test-Path (Join-Path $desk 'connect-version.txt')) {
  Write-Host ('desk_ver=' + (Get-Content (Join-Path $desk 'connect-version.txt') -Raw).Trim())
}
$cps = Get-Content (Join-Path $desk 'connect.ps1') -Raw
Write-Host ('desk_ConnectVersion=' + ([regex]::Match($cps, "ConnectVersion = '([^']+)'").Groups[1].Value))
Write-Host ('desk_has_sidecar_dot=' + ($cps -match 'cursor-proxy-sidecar'))
Write-Host ('desk_has_CLEAR_SKIP=' + ((Get-Content (Join-Path $desk 'editor-launch.ps1') -Raw) -match 'CLEAR_SKIP'))

Write-Host '=== publish folders versions ==='
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
Get-ChildItem $pub -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 8 | ForEach-Object {
  $vf = Join-Path $_.FullName 'windows\connect-version.txt'
  if (-not (Test-Path $vf)) { $vf = Join-Path $_.FullName 'connect-version.txt' }
  $v = if (Test-Path $vf) { (Get-Content $vf -Raw).Trim() } else { 'NO_VER' }
  Write-Host ("{0} => {1}" -f $_.Name, $v)
}

Write-Host '=== common old launch paths ==='
$candidates = @(
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows'),
  (Join-Path $env:USERPROFILE 'OneDrive\Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Downloads\claude-code-client'),
  'D:\Smart\Claude-Code-Server\scripts\client\windows'
)
foreach ($c in $candidates) {
  if (-not (Test-Path $c)) { Write-Host "MISS $c"; continue }
  $vf = Join-Path $c 'connect-version.txt'
  $v = if (Test-Path $vf) { (Get-Content $vf -Raw).Trim() } else { '?' }
  $hasSide = Test-Path (Join-Path $c 'cursor-proxy-sidecar.ps1')
  $upd = Test-Path (Join-Path $c 'connect-update.ps1')
  Write-Host ("PATH $c ver=$v sidecar=$hasSide update=$upd")
}

Write-Host '=== recent UPDATE log lines ==='
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
if (Test-Path $log) {
  Select-String -Path $log -Pattern 'UPDATE_|Client update|up_to_date|OPTIONAL|FORCE|content_mismatch|unavailable|unreachable' |
    Select-Object -Last 40 | ForEach-Object { $_.Line }
}
