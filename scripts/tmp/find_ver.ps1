$root = 'D:\Smart\Claude-Code-Server'
Write-Host '==== find version files ===='
Get-ChildItem -Path $root -Recurse -Filter '*version*' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|dist|bin)\\' } |
  Select-Object -First 40 FullName, Length, LastWriteTime |
  ForEach-Object { "{0}  {1}" -f $_.LastWriteTime.ToString('u'), $_.FullName }

Write-Host '==== CONNECT_VERSION in repo ===='
Select-String -Path "$root\scripts\client\**\*.ps1","$root\scripts\client\**\*.sh","$root\publish\*" -Pattern "CONNECT_VERSION|20260717\.\d+" -ErrorAction SilentlyContinue |
  Select-Object -First 40 |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '==== publish connect-version path ===='
Select-String -Path "$root\publish\publish.ps1" -Pattern "connect-version|CONNECT_VERSION" |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
