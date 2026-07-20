Write-Output ("repo_win=" + (Select-String -Path scripts/client/windows/connect.ps1 -Pattern "ConnectVersion" | Select-Object -First 1).Line.Trim())
Write-Output ("repo_mac=" + (Select-String -Path scripts/client/mac/connect.sh -Pattern "CONNECT_VERSION" | Select-Object -First 1).Line.Trim())
$base = Join-Path $env:USERPROFILE "Desktop\claude-publish"
if (Test-Path $base) {
  Get-ChildItem $base -Directory | Sort-Object Name -Descending | Select-Object -First 10 | ForEach-Object {
    $candidates = @(
      (Join-Path $_.FullName "connect-version.txt"),
      (Join-Path $_.FullName "windows\connect-version.txt"),
      (Join-Path $_.FullName "claude-code\windows\connect-version.txt"),
      (Join-Path $_.FullName "mac\connect-version.txt")
    )
    $ver = "?"
    foreach ($v in $candidates) {
      if (Test-Path $v) { $ver = (Get-Content $v -Raw).Trim(); break }
    }
    Write-Output ("pub=" + $_.Name + " ver=" + $ver)
  }
} else { Write-Output "no Desktop\claude-publish" }
