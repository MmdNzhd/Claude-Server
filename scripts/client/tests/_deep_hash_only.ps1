$ErrorActionPreference = 'Stop'
$pairs = @(
  @('D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1', (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\git-mode.ps1')),
  @('D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1', (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect-ui.ps1')),
  @('D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1', (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect.ps1')),
  @('D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1', (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\editor-launch.ps1')),
  @('D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1', (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\cursor-auth-laptop.ps1'))
)
$sha = [Security.Cryptography.SHA256]::Create()
foreach ($p in $pairs) {
  $ha = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($p[0])))).Replace('-','').Substring(0,12)
  $hb = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($p[1])))).Replace('-','').Substring(0,12)
  Write-Host ("EQ={0} {1} {2}/{3}" -f ($ha -eq $hb), (Split-Path $p[1] -Leaf), $ha, $hb)
}
# Shallow sepidz bat check (no full Desktop recurse)
$paths = @(
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz\claude-code\windows\connect.bat'),
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Sepidz\connect.bat'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\_QUARANTINE_SEPIDZ_20260722-201938\claude-code-sepidz\claude-code\windows\connect.bat')
)
foreach ($p in $paths) {
  Write-Host ("exists_live={0} path={1}" -f (Test-Path -LiteralPath $p), $p)
  Write-Host ("exists_disabled={0}" -f (Test-Path -LiteralPath ($p + '.DISABLED')))
}
