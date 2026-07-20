$paths = @(
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.log',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect.log',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.log',
  'D:\Smart\Claude-Code-Server\logs\connect.log'
)
Get-ChildItem 'C:\Users\Smart\Desktop\claude-publish' -Recurse -Filter connect.log -ErrorAction SilentlyContinue |
  ForEach-Object { Write-Host "$($_.LastWriteTime) $($_.Length) $($_.FullName)" }
Get-ChildItem 'D:\Smart\Claude-Code-Server' -Recurse -Filter connect.log -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch 'node_modules' } |
  ForEach-Object { Write-Host "$($_.LastWriteTime) $($_.Length) $($_.FullName)" }
