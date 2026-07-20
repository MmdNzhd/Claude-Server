$ErrorActionPreference = 'Continue'
# Narrow searches - no deep D:\Smart recurse
$roots = @(
  "$env:USERPROFILE\Desktop",
  "$env:USERPROFILE\Downloads",
  "$env:USERPROFILE\Documents",
  "$env:TEMP",
  "D:\temp",
  "D:\Smart\Desktop",
  "$env:USERPROFILE\AppData\Local\Temp"
)
Write-Output '=== connect logs recent ==='
foreach ($r in $roots) {
  if (-not (Test-Path $r)) { continue }
  Get-ChildItem -Path $r -Filter '*connect*.log' -File -EA SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) } |
    ForEach-Object { "{0}`t{1}`t{2}" -f $_.LastWriteTime.ToString('s'), $_.Length, $_.FullName }
  Get-ChildItem -Path $r -Filter '*azin*' -Recurse -Depth 2 -EA SilentlyContinue |
    Select-Object -First 20 |
    ForEach-Object { "AZIN_NAME`t$($_.FullName)" }
}
# Telegram Desktop common path
$tg = @(
  "$env:USERPROFILE\Downloads\Telegram Desktop",
  "D:\Telegram Desktop",
  "$env:USERPROFILE\Desktop\Telegram Desktop"
)
foreach ($r in $tg) {
  if (-not (Test-Path $r)) { continue }
  Write-Output "=== TG $r ==="
  Get-ChildItem -Path $r -Filter '*connect*' -File -EA SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 15 |
    ForEach-Object { "{0}`t{1}`t{2}" -f $_.LastWriteTime.ToString('s'), $_.Length, $_.Name }
  Get-ChildItem -Path $r -Filter '*azin*' -File -EA SilentlyContinue |
    ForEach-Object { "AZIN`t$($_.Name)" }
}
# Search claude logs dir pattern under users if accessible - skip
Write-Output '=== done ==='
