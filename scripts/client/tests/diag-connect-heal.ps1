$ErrorActionPreference = 'Continue'
$oldWin = 'C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$desk = 'C:\Users\Smart\Desktop\Claude-Connect'
$oldBat = Join-Path $oldWin 'connect.bat'
$newBat = Join-Path $desk 'connect.bat'
Write-Output '=== OLD connect.bat (first 60 lines) ==='
if (Test-Path -LiteralPath $oldBat) {
  Get-Content -LiteralPath $oldBat -TotalCount 60
  $ol = (Get-Item -LiteralPath $oldBat).Length
} else { Write-Output 'MISSING'; $ol = -1 }
Write-Output '=== LENGTHS ==='
if (Test-Path -LiteralPath $newBat) {
  $nl = (Get-Item -LiteralPath $newBat).Length
  Write-Output ("OLD_BAT_BYTES=" + $ol)
  Write-Output ("DESK_BAT_BYTES=" + $nl)
} else { Write-Output ("OLD_BAT_BYTES=" + $ol); Write-Output 'DESK_BAT_MISSING=1' }
Write-Output '=== connect-version.txt ==='
$oldRoot = 'C:\Users\Smart\Downloads\claude-code-client-20260715'
foreach ($pair in @(
  @{L='OLD_ROOT'; P=(Join-Path $oldRoot 'connect-version.txt')},
  @{L='OLD_WIN'; P=(Join-Path $oldWin 'connect-version.txt')},
  @{L='DESK'; P=(Join-Path $desk 'connect-version.txt')}
)) {
  $p = $pair.P
  if (Test-Path -LiteralPath $p) {
    Write-Output ($pair.L + ': ' + (Get-Content -LiteralPath $p -Raw).Trim())
  } else { Write-Output ($pair.L + ': MISSING') }
}
Write-Output '=== HEAL/BOOTSTRAP in old windows folder ==='
foreach ($f in @('connect-bootstrap.ps1','connect-heal.ps1')) {
  $fp = Join-Path $oldWin $f
  if (Test-Path -LiteralPath $fp) { Write-Output ($f + ' EXISTS len=' + (Get-Item -LiteralPath $fp).Length) }
  else { Write-Output ($f + ' MISSING') }
}
Write-Output '=== OLD BAT bootstrap/heal references ==='
if (Test-Path -LiteralPath $oldBat) {
  $lines = Get-Content -LiteralPath $oldBat
  $boot = ($lines | Select-String -Pattern 'bootstrap' -SimpleMatch).Count -gt 0
  $heal = ($lines | Select-String -Pattern 'heal' -SimpleMatch).Count -gt 0
  Write-Output ('calls_bootstrap=' + $boot)
  Write-Output ('calls_heal=' + $heal)
}
