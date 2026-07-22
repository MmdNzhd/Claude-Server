$ErrorActionPreference = 'Continue'
function Check-Loc([string]$label, [string]$winDir, [string]$macDir) {
  Write-Host "---"
  Write-Host $label
  $boot = Join-Path $winDir 'connect-boot.ps1'
  $ver = Join-Path $winDir 'connect-version.txt'
  $ps1 = Join-Path $winDir 'connect.ps1'
  $bat = Join-Path $winDir 'connect.bat'
  Write-Host ("  winDir exists: " + (Test-Path -LiteralPath $winDir))
  Write-Host ("  connect-boot: " + (Test-Path -LiteralPath $boot))
  if (Test-Path -LiteralPath $ver) {
    Write-Host ("  win connect-version.txt: " + (Get-Content -LiteralPath $ver -Raw).Trim())
  } else {
    Write-Host '  win connect-version.txt: MISSING'
  }
  if (Test-Path -LiteralPath $ps1) {
    $line = Select-String -LiteralPath $ps1 -Pattern "ConnectVersion\s*=\s*'([^']+)'" | Select-Object -First 1
    if ($line) {
      Write-Host ("  connect.ps1 ConnectVersion: " + $line.Matches[0].Groups[1].Value)
    } else {
      Write-Host '  connect.ps1 ConnectVersion: NOT_FOUND'
    }
  } else {
    Write-Host '  connect.ps1: MISSING'
  }
  if (Test-Path -LiteralPath $bat) {
    $hasBoot = Select-String -LiteralPath $bat -Pattern 'connect-boot.ps1' -Quiet
    Write-Host ("  connect.bat references connect-boot: " + $hasBoot)
  }
  if ($macDir -and (Test-Path -LiteralPath $macDir)) {
    $mv = Join-Path $macDir 'connect-version.txt'
    $msh = Join-Path $macDir 'connect.sh'
    if (Test-Path -LiteralPath $mv) {
      Write-Host ("  mac connect-version.txt: " + (Get-Content -LiteralPath $mv -Raw).Trim())
    }
    if (Test-Path -LiteralPath $msh) {
      $mm = Select-String -LiteralPath $msh -Pattern "CONNECT_VERSION='([^']+)'" | Select-Object -First 1
      if ($mm) {
        Write-Host ("  connect.sh CONNECT_VERSION: " + $mm.Matches[0].Groups[1].Value)
      }
    }
  }
}

$desk = [Environment]::GetFolderPath('Desktop')
Check-Loc 'Desktop/claude-connect (flat live)' (Join-Path $desk 'claude-connect') (Join-Path $desk 'claude-connect\mac')
Check-Loc 'Desktop/Claude-Connect' (Join-Path $desk 'Claude-Connect') (Join-Path $desk 'Claude-Connect\mac')

$pubRoot = Join-Path $desk 'claude-publish'
Write-Host '---'
Write-Host 'publish dirs:'
Get-ChildItem -LiteralPath $pubRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { Write-Host ('  ' + $_.Name) }

$latest = Get-ChildItem -LiteralPath $pubRoot -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'claude-code-client-*' } |
  Sort-Object Name |
  Select-Object -Last 1
if ($latest) {
  Check-Loc ("LATEST publish " + $latest.Name) (Join-Path $latest.FullName 'windows') (Join-Path $latest.FullName 'mac')
}

$v25 = Join-Path $pubRoot 'claude-code-client-20260720'
if (Test-Path -LiteralPath $v25) {
  Check-Loc 'publish claude-code-client-20260720' (Join-Path $v25 'windows') (Join-Path $v25 'mac')
}

Write-Host '---'
Write-Host 'recent zips:'
Get-ChildItem -LiteralPath $pubRoot -Filter '*.zip' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime |
  Select-Object -Last 10 |
  ForEach-Object { Write-Host ('  ' + $_.Name + ' | ' + $_.LastWriteTime.ToString('s')) }
