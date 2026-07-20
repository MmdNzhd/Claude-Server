$ErrorActionPreference='Continue'
Get-ChildItem scripts/client -Recurse -Include *.ps1 | ForEach-Object {
  Select-String -Path $_.FullName -Pattern 'connection dropped' -SimpleMatch -ErrorAction SilentlyContinue |
    ForEach-Object { '{0}:{1}: {2}' -f $_.Path.Replace((Get-Location).Path+'\',''), $_.LineNumber, $_.Line.Trim() }
}
Select-String -Path 'scripts/client/windows/connect.ps1' -Pattern 'ConnectVersion' | Select-Object -First 3 | ForEach-Object { $_.Line }
