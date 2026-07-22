$ErrorActionPreference = 'Stop'
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
foreach ($pair in @(
  @{L='OLD'; P=(Join-Path $oldWin '..\connect-version.txt')},
  @{L='OLD_WIN'; P=(Join-Path $oldWin 'connect-version.txt')},
  @{L='DESK'; P=(Join-Path $desk 'connect-version.txt')}
)) {
  $p = $pair.P
  if (Test-Path -LiteralPath $p) {
    Write-Output ($pair.L + ': ' + (Get-Content -LiteralPath $p -Raw).Trim())
  } else { Write-Output ($pair.L + ': MISSING path=' + $p) }
}
Write-Output '=== HEAL/BOOTSTRAP in old windows folder ==='
foreach ($f in @('connect-bootstrap.ps1','connect-heal.ps1')) {
  $fp = Join-Path $oldWin $f
  if (Test-Path -LiteralPath $fp) { Write-Output ($f + ' EXISTS len=' + (Get-Item -LiteralPath $fp).Length) }
  else { Write-Output ($f + ' MISSING') }
}
Write-Output '=== OLD BAT bootstrap/heal references ==='
if (Test-Path -LiteralPath $oldBat) {
  $txt = Get-Content -LiteralPath $oldBat -Raw
  Write-Output ('calls_bootstrap=' + ($txt -match 'bootstrap'))
  Write-Output ('calls_heal=' + ($txt -match 'heal'))
}
