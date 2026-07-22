$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
Write-Host '=== publish .15 SmartOnly SkipVersionBump ==='
& (Join-Path $root 'publish\publish.ps1') -SmartOnly -SkipVersionBump
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows'
if (-not (Test-Path $pub)) {
  # fallback: find latest publish windows dir
  $candidates = Get-ChildItem (Join-Path $env:USERPROFILE 'Desktop\claude-publish') -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'claude-code-client-*' } |
    Sort-Object LastWriteTime -Descending
  foreach ($c in $candidates) {
    $w = Join-Path $c.FullName 'windows'
    if (Test-Path (Join-Path $w 'connect.ps1')) { $pub = $w; break }
  }
}
Write-Host ("PUB_DIR={0}" -f $pub)
$targets = @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows')
)
$files = @(
  'connect.bat','connect-boot.ps1','connect-version.txt','connect-update.ps1','connect.ps1',
  'connect-ui.ps1','git-mode.ps1','editor-launch.ps1','cursor-auth-laptop.ps1','connect-diagnostic.ps1'
)
foreach ($t in $targets) {
  if (-not (Test-Path $t)) { Write-Host ("SKIP missing {0}" -f $t); continue }
  New-Item -ItemType Directory -Force -Path $t | Out-Null
  foreach ($f in $files) {
    $src = Join-Path $pub $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $t $f) -Force }
  }
  $ver = (Get-Content (Join-Path $t 'connect-version.txt') -Raw -ErrorAction SilentlyContinue).Trim()
  $raw = Get-Content (Join-Path $t 'git-mode.ps1') -Raw
  $cn = Get-Content (Join-Path $t 'connect.ps1') -Raw
  Write-Host ("SYNC {0} ver={1} tcp_open_reuse={2} bg_skip={3} auth_ttl={4}" -f $t, $ver,
    [int]($raw -match 'recent_success_tcp_open'),
    [int]($cn -match 'bg_init_same_pick'),
    [int]((Get-Content (Join-Path $t 'cursor-auth-laptop.ps1') -Raw) -match 'local_ttl'))
}
