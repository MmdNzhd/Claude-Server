
$paths = @(
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\windows\connect.ps1',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\mac\connect.sh'
)
foreach($p in $paths){
  Write-Host "==== $p"
  Select-String -Path $p -Pattern 'Alias|RemoteUser|ServerIP|ALIAS=|SERVER_IP|REMOTE_USER' |
    Select-Object -First 20 |
    ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }
}
