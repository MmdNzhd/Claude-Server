$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
function Sha16([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return 'MISSING' }
  return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 16)
}
$pairs = @(
  @('scripts\client\connect-ui.ps1', 'scripts\client\windows\connect-ui.ps1'),
  @('scripts\client\connect-diagnostic.ps1', 'scripts\client\windows\connect-diagnostic.ps1')
)
foreach ($pair in $pairs) {
  $a = Join-Path $root $pair[0]
  $b = Join-Path $root $pair[1]
  $sa = Sha16 $a; $sb = Sha16 $b
  Write-Output ("SHADOW {0} canon={1} win={2} same={3}" -f $pair[0], $sa, $sb, ($sa -eq $sb))
}
$sidecar = Join-Path $root 'scripts\client\windows\cursor-proxy-sidecar.ps1'
$txt = Get-Content -LiteralPath $sidecar -Raw
$names = @(
  'function Start-CursorProxySidecarWatchdog',
  'function Stop-CursorProxySidecarWatchdog',
  'function Stop-CursorProxySidecar',
  'function Reap-Sidecar',
  'function Ensure-CursorProxySidecar',
  'function Start-CursorProxySidecar'
)
foreach ($n in $names) {
  Write-Output ("SIDECAR {0} = {1}" -f $n, [bool]($txt -match [regex]::Escape($n)))
}
$tests = Join-Path $root 'scripts\client\tests'
$scratch = @(Get-ChildItem -LiteralPath $tests -Filter '_*.ps1' -File -ErrorAction SilentlyContinue)
Write-Output ("SCRATCH_COUNT={0}" -f $scratch.Count)
Write-Output ("SCRATCH_KEEP_paths={0}" -f (@($scratch | Where-Object { $_.Name -eq '_paths.ps1' }).Count))
$del = @($scratch | Where-Object { $_.Name -ne '_paths.ps1' } | Select-Object -ExpandProperty Name | Sort-Object)
Write-Output ("SCRATCH_DELETE_SAMPLE={0}" -f (($del | Select-Object -First 12) -join ','))
# publish copy sources
$pub = Join-Path $root 'publish\publish.ps1'
Select-String -LiteralPath $pub -Pattern 'connect-ui|connect-diagnostic|cursor-proxy-sidecar' | ForEach-Object {
  Write-Output ("PUBLISH: {0}" -f $_.Line.Trim())
}
# low-ref helper files mention
foreach ($rel in @(
  'scripts\client\sync-desktop.ps1',
  'scripts\client\cursor-profile-db-tool.ps1',
  'scripts\client\windows\connect-design.ps1'
)) {
  $p = Join-Path $root $rel
  Write-Output ("FILE_EXISTS {0}={1}" -f $rel, (Test-Path -LiteralPath $p))
}
# function hit counts across client ps1 (excluding tests/_*)
$clientFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts\client') -Recurse -Filter '*.ps1' -File |
  Where-Object { $_.FullName -notmatch '\\tests\\_' })
$funcs = @(
  'Get-TunnelBanner','Clear-TunnelBannerCache','Ensure-SessionTunnel','Acquire-TunnelPort',
  'Sync-CursorGoldenAuth','Test-CursorAuthNeedsRefresh','Start-CursorProxySidecarWatchdog',
  'Add-ClearedTunnelPort','Push-LaptopExecBundleIfChanged','Try-ReattachSessionTunnelProcess',
  'Show-ConnectUi','Write-ConnectSessionBox'
)
foreach ($f in $funcs) {
  $hits = 0
  foreach ($file in $clientFiles) {
    $c = Select-String -LiteralPath $file.FullName -Pattern $f -SimpleMatch -ErrorAction SilentlyContinue
    if ($c) { $hits += @($c).Count }
  }
  Write-Output ("HITS {0}={1}" -f $f, $hits)
}
