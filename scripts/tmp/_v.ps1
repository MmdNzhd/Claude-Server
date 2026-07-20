$w=(Select-String -Path scripts/client/windows/connect.ps1 -Pattern "ConnectVersion\s*=" | Select-Object -First 1).Line.Trim()
$m=(Select-String -Path scripts/client/mac/connect.sh -Pattern "^CONNECT_VERSION=" | Select-Object -First 1).Line.Trim()
Write-Output $w
Write-Output $m
$base=Join-Path $env:USERPROFILE 'Desktop\claude-publish'
Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
  $vFile=@(
    (Join-Path $_.FullName 'connect-version.txt'),
    (Join-Path $_.FullName 'windows\connect-version.txt')
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  $ver= if($vFile){(Get-Content $vFile -Raw).Trim()} else {'?'}
  Write-Output ("desk=" + $_.Name + " ver=" + $ver + " mtime=" + $_.LastWriteTime.ToString('s'))
}
