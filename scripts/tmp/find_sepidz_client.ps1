$ErrorActionPreference='Continue'
Write-Host "=== Desktop dirs ==="
Get-ChildItem "$env:USERPROFILE\Desktop" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_.FullName }
Write-Host "=== Search connect.bat ==="
@(
  "$env:USERPROFILE\Desktop",
  "$env:USERPROFILE\Documents",
  "D:\Smart",
  "C:\Users\Smart"
) | ForEach-Object {
  if (Test-Path $_) {
    Get-ChildItem $_ -Recurse -Filter connect.bat -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notmatch '\\node_modules\\|\\Claude-Code-Server\\' } |
      Select-Object -First 15 |
      ForEach-Object {
        $dir = $_.DirectoryName
        $vf = Join-Path $dir 'connect-version.txt'
        $ver = if (Test-Path $vf) { (Get-Content $vf -Raw).Trim() } else { '?' }
        Write-Host ("bat=$($_.FullName) ver=$ver")
      }
  }
}
Write-Host "=== publish help ==="
Select-String -Path publish\publish.ps1 -Pattern 'SepidzOnly|param\(|DeployTarget|192\.168\.250' |
  Select-Object -First 30 |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
