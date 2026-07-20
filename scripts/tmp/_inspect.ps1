$root = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717'
Write-Output "exists=$([bool](Test-Path $root))"
if (Test-Path $root) {
  Get-ChildItem $root -Recurse -File | Select-Object -First 40 | ForEach-Object {
    Write-Output $_.FullName.Substring($root.Length).TrimStart('\')
  }
  $vf = Get-ChildItem $root -Recurse -Filter connect-version.txt | Select-Object -First 3
  foreach ($f in $vf) {
    Write-Output ("VERFILE=" + $f.FullName + " => " + (Get-Content $f.FullName -Raw).Trim())
  }
  # peek connect versions in ps1/sh
  $ps1 = Join-Path $root 'windows\connect.ps1'
  if (-not (Test-Path $ps1)) { $ps1 = Join-Path $root 'connect.ps1' }
  $sh = Join-Path $root 'mac\connect.sh'
  if (Test-Path $ps1) {
    Write-Output ("ps1=" + (Select-String -Path $ps1 -Pattern 'ConnectVersion' | Select-Object -First 1).Line.Trim())
  }
  if (Test-Path $sh) {
    Write-Output ("sh=" + (Select-String -Path $sh -Pattern '^CONNECT_VERSION=' | Select-Object -First 1).Line.Trim())
  }
}
