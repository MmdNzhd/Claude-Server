$ErrorActionPreference = 'Continue'
$root = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
Get-ChildItem $root -Recurse -Filter 'connect.bat' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match 'sepidz|Sepidz|QUARANTINE' -and $_.Name -eq 'connect.bat' } |
  ForEach-Object {
    $dis = $_.FullName + '.DISABLED'
    try {
      if (Test-Path $dis) { Remove-Item -LiteralPath $dis -Force }
      Rename-Item -LiteralPath $_.FullName -NewName 'connect.bat.DISABLED' -Force
      Write-Host ("DISABLED " + $_.FullName)
    } catch { Write-Host ("FAIL " + $_.FullName + " :: " + $_.Exception.Message) }
  }
# verify none live
$live = @(Get-ChildItem (Join-Path $env:USERPROFILE 'Desktop') -Recurse -Filter 'connect.bat' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match 'sepidz|Sepidz' -and $_.Name -eq 'connect.bat' })
Write-Host ("remaining_live_sepidz_connect_bat=" + $live.Count)
$live | ForEach-Object { Write-Host ("STILL " + $_.FullName) }

# Hash equality spot-check Desktop vs repo for stage-critical files
$pairs = @(
  @('scripts\client\git-mode.ps1', 'Desktop\Claude-Connect\git-mode.ps1'),
  @('scripts\client\connect-ui.ps1', 'Desktop\Claude-Connect\connect-ui.ps1'),
  @('scripts\client\windows\connect.ps1', 'Desktop\Claude-Connect\connect.ps1'),
  @('scripts\client\editor-launch.ps1', 'Desktop\Claude-Connect\editor-launch.ps1')
)
$repo = 'D:\Smart\Claude-Code-Server'
$deskRoot = $env:USERPROFILE
$sha = [Security.Cryptography.SHA256]::Create()
foreach ($p in $pairs) {
  $a = Join-Path $repo $p[0]
  $b = Join-Path $deskRoot $p[1]
  $ha = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($a)))).Replace('-','').Substring(0,12)
  $hb = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($b)))).Replace('-','').Substring(0,12)
  Write-Host ("EQ={0} {1}" -f ($ha -eq $hb), (Split-Path $p[1] -Leaf))
}
