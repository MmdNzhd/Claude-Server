$log = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.log'
if (-not (Test-Path $log)) { Write-Host "MISSING: $log"; exit 1 }
$i = Get-Item $log
Write-Host "FILE: $($i.FullName)"
Write-Host "SIZE: $($i.Length) LAST: $($i.LastWriteTime)"
Write-Host "---- TAIL 250 ----"
Get-Content $log -Tail 250
