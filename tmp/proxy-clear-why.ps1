$ErrorActionPreference = 'Continue'
$p = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-20260721.log"
# Context around CLEAR 18:44 session 3db7e5c48210
Write-Host '==== CONTEXT around CURSOR_PROXY_CLEAR 18:44 ===='
$all = Get-Content $p
$idx = 0
for ($i=0; $i -lt $all.Count; $i++) {
  if ($all[$i] -match 'CURSOR_PROXY_CLEAR: removed proxy keys') { $idx = $i; break }
}
# find LAST clear
for ($i=0; $i -lt $all.Count; $i++) {
  if ($all[$i] -match 'CURSOR_PROXY_CLEAR: removed proxy keys') { $idx = $i }
}
$start = [Math]::Max(0, $idx - 40)
$end = [Math]::Min($all.Count-1, $idx + 25)
for ($i=$start; $i -le $end; $i++) { $all[$i] }

Write-Host ''
Write-Host '==== Session 3db7e5c48210 full proxy/tunnel lines ===='
Select-String -Path $p -Pattern '\[3db7e5c48210\]' | ForEach-Object { $_.Line } | Where-Object {
  $_ -match 'PROXY|ENSURE_TUNNEL|socks|http_port|CURSOR_|TUNNEL_|session start|CONNECT_VERSION|LAUNCH_|SocksProxy|remote_xray|Clear|SET'
} | ForEach-Object { $_ }

Write-Host ''
Write-Host '==== Evening 18:10-19:10 compact story ===='
Select-String -Path $p -Pattern '\[2026-07-21 18:(1[0-9]|[2-5][0-9]|[0-9][0-9])|\[2026-07-21 19:0' | ForEach-Object { $_.Line } | Where-Object {
  $_ -match 'CURSOR_PROXY_|remote_xray|ENSURE_TUNNEL (spawned|ok=|reuse_proxy|reseed|wait_timeout)|TUNNEL_DROP|LAUNCH_KILL|session start|CONNECT_VERSION|PROXY: enabled|missing_http|skipping_proxy'
} | ForEach-Object { $_ }
