$ErrorActionPreference = 'Continue'
$day = Get-Date -Format 'yyyyMMdd'
$p = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-$day.log"
Write-Host "LOCAL=$p size=$((Get-Item $p).Length) mtime=$((Get-Item $p).LastWriteTime)"

# Extract proxy/tunnel death timeline with session ids
$pat = 'CURSOR_PROXY_|remote_xray|ENSURE_TUNNEL|socks_port|http_port|reuse_proxy|reseed|missing_http|legacy_D|skipping_proxy|TUNNEL_DROP|PROXY:|proxy_leg|wait_timeout|ok=0|Clear|region|permission'
$lines = Select-String -Path $p -Pattern $pat | ForEach-Object { $_.Line }

Write-Host "==== FULL PROXY/TUNNEL TIMELINE (filtered) count=$($lines.Count) ===="
# Focus afternoon/evening Iran time when user hit region + VPN
$focus = $lines | Where-Object {
  $_ -match '\[2026-07-21 (1[5-9]|2[0-3]):' -or $_ -match '\[2026-07-21 1[89]:'
}
# Also include earlier proxy clears
$allProxy = $lines | Where-Object { $_ -match 'CURSOR_PROXY_|remote_xray|skipping_proxy|reuse_proxy|reseed|missing_http|legacy_D|PROXY: enabled|wait_timeout|ok=0' }

Write-Host '---- KEY PROXY DEATH/CHANGE LINES ----'
$allProxy | Select-Object -Last 120 | ForEach-Object { $_ }

Write-Host ''
Write-Host '==== Per-session last socks/http assignment ===='
$sessionMap = @{}
foreach ($line in $lines) {
  if ($line -match '\[([0-9a-f]{12})\]') {
    $sid = $Matches[1]
    if ($line -match 'socks_port=(\d+)|socks=(\d+)|local=(\d+)|proxy=socks5://127\.0\.0\.1:(\d+)|proxy=http://127\.0\.0\.1:(\d+)|http_port=(\d+)|http_local=(\d+)|CURSOR_PROXY_CLEAR|CURSOR_PROXY_SET|remote_xray|skipping_proxy|wait_timeout|ok=0|TUNNEL_DROP') {
      if (-not $sessionMap.ContainsKey($sid)) { $sessionMap[$sid] = New-Object System.Collections.Generic.List[string] }
      if ($sessionMap[$sid].Count -lt 40) { [void]$sessionMap[$sid].Add($line) }
    }
  }
}
# Print sessions that had CLEAR or timeout or drop near proxy
foreach ($sid in ($sessionMap.Keys | Sort-Object)) {
  $arr = $sessionMap[$sid]
  $interesting = $arr | Where-Object { $_ -match 'CLEAR|wait_timeout|ok=0|TUNNEL_DROP|skipping_proxy|remote_xray=closed|reseed|CURSOR_PROXY_SET' }
  if ($interesting) {
    Write-Host "---- session $sid ----"
    $interesting | Select-Object -Last 25 | ForEach-Object { $_ }
  }
}
