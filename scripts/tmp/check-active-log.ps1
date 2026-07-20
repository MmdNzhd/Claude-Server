$ErrorActionPreference='Continue'
$logs = Get-ChildItem -Path 'C:\Users\Smart\Desktop\claude-publish' -Recurse -Filter 'connect.log' -EA SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 5
$repoLog = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.log'
if (Test-Path $repoLog) { $logs = @((Get-Item $repoLog)) + @($logs) }
foreach ($l in $logs) {
  Write-Host ("---- {0} mtime={1} ----" -f $l.FullName, $l.LastWriteTime)
  $tail = Get-Content $l.FullName -Tail 30 -EA SilentlyContinue
  $tail | Select-String -Pattern 'version=2026|ConnectVersion|connection dropped|banner_miss|TUNNEL_BANNER soft|tunnelSyncOk|ENSURE_TUNNEL ok' |
    Select-Object -Last 8 | ForEach-Object { $_.Line }
  $ver = Select-String -Path $l.FullName -Pattern 'version=20260717\.\d+' | Select-Object -Last 1
  if ($ver) { Write-Host ("LAST_VER  " + $ver.Line) }
}
