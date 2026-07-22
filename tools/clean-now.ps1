$ErrorActionPreference = 'Stop'
$desk = Join-Path $env:USERPROFILE 'Desktop'
$win = Join-Path $desk 'claude-publish\claude-code-client\windows'
$canon = Join-Path $desk 'Claude-Connect'
$repoBoot = Join-Path (Get-Location) 'scripts\client\windows\connect-bootstrap.ps1'
$repoUpd = Join-Path (Get-Location) 'scripts\client\windows\connect-update.ps1'

# Sync fixed scripts into live Canon immediately
Copy-Item -LiteralPath $repoBoot -Destination (Join-Path $canon 'connect-bootstrap.ps1') -Force
Copy-Item -LiteralPath $repoUpd -Destination (Join-Path $canon 'connect-update.ps1') -Force
Write-Host 'synced bootstrap+update into Desktop\Claude-Connect'

$exeSrc = Join-Path $canon 'Claude-Connect.exe'
if (-not (Test-Path $exeSrc)) { $exeSrc = Join-Path $desk 'Claude-Connect.exe' }
if (-not (Test-Path $exeSrc)) { $exeSrc = Join-Path $win 'Claude-Connect.exe' }

if (Test-Path $win) {
  Get-ChildItem -LiteralPath $win -Force | ForEach-Object {
    if ($_.Name -in @('Claude-Connect.exe','READ-ME.txt')) { return }
    Remove-Item -LiteralPath $_.FullName -Recurse -Force
    Write-Host ("removed {0}" -f $_.Name)
  }
  if (Test-Path $exeSrc) {
    Copy-Item -LiteralPath $exeSrc -Destination (Join-Path $win 'Claude-Connect.exe') -Force
  }
  $readme = @"
Claude Connect - do not run from this folder
===========================================
This publish/unzip folder is not the live client.

Use:
  Desktop\Claude-Connect.exe
or:
  Desktop\Claude-Connect\connect.bat
"@
  [IO.File]::WriteAllText((Join-Path $win 'READ-ME.txt'), ($readme -replace "`n","`r`n"), [Text.UTF8Encoding]::new($false))
  Write-Host '=== windows folder now ==='
  Get-ChildItem $win | ForEach-Object { Write-Host (" {0}" -f $_.Name) }
} else {
  Write-Host 'windows folder missing'
}
