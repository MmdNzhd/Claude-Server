$ErrorActionPreference = 'Continue'
function Check-Surface([string]$Root, [string]$Label) {
  Write-Output "==== $Label ===="
  Write-Output "path=$Root"
  Write-Output "exists=$(Test-Path -LiteralPath $Root)"
  if (-not (Test-Path -LiteralPath $Root)) { return }

  $verFile = Join-Path $Root 'connect-version.txt'
  if (Test-Path -LiteralPath $verFile) {
    Write-Output ("version_txt=" + (Get-Content -LiteralPath $verFile -Raw).Trim())
  } else {
    Write-Output 'version_txt=MISSING'
  }

  $connectPs1 = Join-Path $Root 'connect.ps1'
  if (Test-Path -LiteralPath $connectPs1) {
    $line = Select-String -LiteralPath $connectPs1 -Pattern "ConnectVersion\s*=\s*'([^']+)'" | Select-Object -First 1
    if ($line) { Write-Output ("connect_ps1_version=" + $line.Matches[0].Groups[1].Value) }
    else { Write-Output 'connect_ps1_version=NOT_FOUND' }
  } else {
    Write-Output 'connect_ps1=MISSING'
  }

  $boot = Join-Path $Root 'connect-boot.ps1'
  Write-Output ("connect_boot=" + (Test-Path -LiteralPath $boot))

  $gm = Join-Path $Root 'git-mode.ps1'
  if (Test-Path -LiteralPath $gm) {
    $c = Get-Content -LiteralPath $gm -Raw
    $g1 = $c -match 'function Test-TunnelPortIsForeignPeer'
    $g2 = $c -match 'function Get-TunnelHostKeyFingerprint'
    $g3 = $c -match 'PUSH_CONF blocked'
    $g4 = $c -match 'refuse_kill_foreign'
    Write-Output ("guards=ForeignPeer=$g1 HostKeyFP=$g2 PUSH_CONF_blocked=$g3 refuse_kill_foreign=$g4")
  } else {
    Write-Output 'git-mode.ps1=MISSING'
  }
}

$desk = Join-Path $env:USERPROFILE 'Desktop'
Check-Surface (Join-Path $desk 'Claude-Connect') 'Claude-Connect'
Check-Surface (Join-Path $desk 'claude-publish\claude-code-client-20260717\windows') 'publish-20260717-windows'
Check-Surface (Join-Path $desk 'claude-publish\claude-code-client-20260721') 'publish-20260721-root'
Check-Surface (Join-Path $desk 'claude-publish\claude-code-client-20260721\windows') 'publish-20260721-windows'
Check-Surface (Join-Path $desk 'claude-publish\claude-code-client-20260721\claude-code\windows') 'publish-20260721-claude-code-windows'

# Also list publish folder children
$pub = Join-Path $desk 'claude-publish'
Write-Output '==== publish-listing ===='
if (Test-Path -LiteralPath $pub) {
  Get-ChildItem -LiteralPath $pub | ForEach-Object { Write-Output ($_.Mode + ' ' + $_.Name) }
} else {
  Write-Output 'MISSING'
}

# Laptop connect.conf
$cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
Write-Output '==== laptop-connect.conf ===='
Write-Output "path=$cfg"
Write-Output "exists=$(Test-Path -LiteralPath $cfg)"
if (Test-Path -LiteralPath $cfg) {
  Get-Content -LiteralPath $cfg
}
