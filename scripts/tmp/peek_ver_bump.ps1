$root='D:\Smart\Claude-Code-Server'
Write-Host 'windows=' ((Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim())
Write-Host 'mac=' ((Get-Content "$root\scripts\client\mac\connect-version.txt" -Raw).Trim())
Select-String -Path "$root\publish\bump-connect-version.ps1" -Pattern 'function |param|Version|yyyyMMdd|Get-Date' |
  Select-Object -First 40 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
