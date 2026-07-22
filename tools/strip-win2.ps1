$ErrorActionPreference='Stop'
$OutDir = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client'
$exe = Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe' }
$win = Join-Path $OutDir 'windows'
Get-ChildItem $win -Force | ForEach-Object {
  if ($_.Name -in @('Claude-Connect.exe','READ-ME.txt')) { return }
  Remove-Item $_.FullName -Recurse -Force
  Write-Host ("removed {0}" -f $_.Name)
}
Copy-Item $exe (Join-Path $win 'Claude-Connect.exe') -Force
@'
Claude Connect - do not run from this folder
===========================================
This publish folder is not for end users.

Give users:
  Desktop\Claude-Connect.exe

Live install after first run:
  Desktop\Claude-Connect\
'@ | Set-Content (Join-Path $win 'READ-ME.txt') -Encoding UTF8
Write-Host '=== now ==='
Get-ChildItem $win | ForEach-Object { $_.Name }
# Sync latest bootstrap from repo into Canon
$canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
Copy-Item 'scripts\client\windows\connect-bootstrap.ps1' (Join-Path $canon 'connect-bootstrap.ps1') -Force
Copy-Item 'scripts\client\windows\connect-update.ps1' (Join-Path $canon 'connect-update.ps1') -Force
Write-Host 'canon synced'
Write-Host ("server bundle ver={0}" -f (Get-Content '/usr/local/share/claude-client/connect-version.txt' -EA SilentlyContinue))
