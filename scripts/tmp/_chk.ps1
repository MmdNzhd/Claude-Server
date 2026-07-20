$base = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'claude-code-client-*' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 3 |
  ForEach-Object {
    $vf = Join-Path $_.FullName 'connect-version.txt'
    $ver = if (Test-Path $vf) { (Get-Content $vf -Raw).Trim() } else { '?' }
    Write-Output ("dir=" + $_.Name + " ver=" + $ver + " mtime=" + $_.LastWriteTime.ToString('s'))
  }
Get-ChildItem $base -Filter 'claude-code-client-*.zip' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 3 |
  ForEach-Object { Write-Output ("zip=" + $_.Name + " mtime=" + $_.LastWriteTime.ToString('s') + " size=" + $_.Length) }
