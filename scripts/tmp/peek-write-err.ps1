Select-String -Path 'D:\Smart\Claude-Code-Server\publish\publish.ps1' -Pattern 'function Write-Err|Write-Err' |
  Select-Object -First 15 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
(Get-Content 'D:\Smart\Claude-Code-Server\publish\publish.ps1')[100..130]
