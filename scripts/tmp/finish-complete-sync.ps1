$ErrorActionPreference = 'Stop'
$repo = 'D:\Smart\Claude-Code-Server'
$ver = '20260715.18'
$el = Join-Path $repo 'scripts\client\editor-launch.ps1'
$winPs1 = Join-Path $repo 'scripts\client\windows\connect.ps1'
$winVer = Join-Path $repo 'scripts\client\windows\connect-version.txt'
$macSh = Join-Path $repo 'scripts\client\mac\connect.sh'

# 1) mac connect-version.txt (published copy must match windows)
$macVerPath = Join-Path $repo 'scripts\client\mac\connect-version.txt'
Set-Content -Path $macVerPath -Value $ver -Encoding ascii -NoNewline
Write-Host "Wrote mac/connect-version.txt = $ver"

# 2) Sync Sepidz Desktop package 20260715
$sepid = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows'
if (Test-Path $sepid) {
  Copy-Item $el (Join-Path $sepid 'editor-launch.ps1') -Force
  # Sepidz connect.ps1 is IP-patched — only bump version string, keep IP
  $sepPs1 = Join-Path $sepid 'connect.ps1'
  $t = Get-Content $sepPs1 -Raw
  $t2 = $t -replace "ConnectVersion = '20260715\.\d+'", "ConnectVersion = '$ver'"
  if ($t2 -eq $t -and $t -notmatch [regex]::Escape("ConnectVersion = '$ver'")) {
    throw 'Sepidz connect.ps1 version bump failed'
  }
  # Keep Sepidz IP
  if ($t2 -notmatch '192\.168\.250\.70') { throw 'Sepidz IP lost during bump' }
  if ($t2 -match '192\.168\.210\.240') { throw 'Smart IP leaked into Sepidz package' }
  Set-Content -Path $sepPs1 -Value $t2 -Encoding UTF8 -NoNewline
  Set-Content -Path (Join-Path $sepid 'connect-version.txt') -Value $ver -Encoding ascii -NoNewline
  # also mac side of sepidz package
  $sepidMac = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\mac'
  if (Test-Path $sepidMac) {
    if (Test-Path (Join-Path $sepidMac 'connect-version.txt')) {
      Set-Content -Path (Join-Path $sepidMac 'connect-version.txt') -Value $ver -Encoding ascii -NoNewline
    }
    $macSep = Join-Path $sepidMac 'connect.sh'
    if (Test-Path $macSep) {
      $ms = Get-Content $macSep -Raw
      $ms2 = $ms -replace "CONNECT_VERSION='20260715\.\d+'", "CONNECT_VERSION='$ver'"
      if ($ms2 -match '192\.168\.210\.240') { throw 'Smart IP in Sepidz mac connect.sh' }
      Set-Content -Path $macSep -Value $ms2 -Encoding UTF8 -NoNewline
    }
  }
  Write-Host 'Synced Sepidz Desktop package to v20260715.18 + kill-fix'
} else {
  Write-Host 'WARN: Sepidz Desktop package folder missing'
}

# 3) Re-verify critical copies
$checks = @(
  @{ Path = $el; Need = 'preserve_open_windows'; Ban = "pre_launch_agent_or_new_window' -Force" },
  @{ Path = (Join-Path 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows' 'editor-launch.ps1'); Need = 'preserve_open_windows'; Ban = "pre_launch_agent_or_new_window' -Force" },
  @{ Path = (Join-Path $sepid 'editor-launch.ps1'); Need = 'preserve_open_windows'; Ban = "pre_launch_agent_or_new_window' -Force" }
)
foreach ($c in $checks) {
  if (-not (Test-Path $c.Path)) { throw "missing $($c.Path)" }
  $r = Get-Content $c.Path -Raw
  if ($r -notmatch $c.Need) { throw "missing preserve in $($c.Path)" }
  if ($r -match [regex]::Escape($c.Ban)) { throw "ban present in $($c.Path)" }
  Write-Host "OK $($c.Path)"
}
$macVer = (Get-Content $macVerPath -Raw).Trim()
if ($macVer -ne $ver) { throw "mac ver=$macVer" }
$sepVer = (Get-Content (Join-Path $sepid 'connect-version.txt') -Raw).Trim()
if ($sepVer -ne $ver) { throw "sepid ver=$sepVer" }
Write-Host "mac + sepidz versions OK ($ver)"
Write-Host 'DONE'
