$desk = Join-Path $env:USERPROFILE "Desktop\Claude-Connect"
Write-Output "=== Desktop layout ==="
Get-ChildItem $desk -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
$ps1 = Join-Path $desk "connect.ps1"
if (Test-Path $ps1) {
  Write-Output "=== connect.ps1 ConnectVersion ==="
  Select-String -Path $ps1 -Pattern "ConnectVersion" | Select-Object -First 1
}
$bat = Join-Path $desk "connect.bat"
if (Test-Path $bat) {
  Write-Output "=== connect.bat guard ==="
  Select-String -Path $bat -Pattern "ConnectVersion|EXPECT_VER" | Select-Object -First 3
}
