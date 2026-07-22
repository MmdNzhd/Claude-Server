$ErrorActionPreference='Continue'
$roots = @(
  (Join-Path $env:USERPROFILE '.cursor'),
  (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'),
  (Join-Path $env:APPDATA 'Cursor')
)
Write-Host '=== mcp.json locations ==='
foreach ($r in $roots) {
  if (-not (Test-Path $r)) { continue }
  Get-ChildItem $r -Recurse -Filter 'mcp.json' -EA SilentlyContinue | ForEach-Object {
    Write-Host ("FILE " + $_.FullName + " size=" + $_.Length)
    $raw = Get-Content $_.FullName -Raw -EA SilentlyContinue
    # redact secrets
    $safe = $raw -replace '(Bearer )[^\s\"]+','$1***' -replace '("SQLSERVER_PASSWORD"\s*:\s*")[^"]+','$1***' -replace '("Authorization"\s*:\s*")[^"]+','$1***'
    Write-Host $safe
    Write-Host '---'
  }
}
Write-Host '=== settings proxy / noProxy ==='
$s = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
if (Test-Path $s) {
  $j = Get-Content $s -Raw | ConvertFrom-Json
  foreach ($k in @('http.proxy','http.proxySupport','http.noProxy','http.proxyStrictSSL','cursor.general.disableHttp2','mcp')) {
    $p = $j.PSObject.Properties[$k]
    if ($p) { Write-Host ("$k = $($p.Value)") }
  }
  # dump keys containing proxy or mcp
  $j.PSObject.Properties | Where-Object { $_.Name -match 'proxy|mcp|MCP' } | ForEach-Object {
    Write-Host ("KEY $($_.Name)=$($_.Value)")
  }
}
Write-Host '=== recent MCP errors from structured log ==='
$logRoot = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\logs'
$latest = Get-ChildItem $logRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-ChildItem $latest.FullName -Recurse -File -EA SilentlyContinue |
  Where-Object { $_.Name -match 'mcp|Structured|network' -and $_.Length -gt 0 } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 8 | ForEach-Object {
    Write-Host ("--- $($_.FullName) ---")
    Get-Content $_.FullName -Tail 40 | ForEach-Object {
      $_ -replace 'Bearer [A-Za-z0-9._\-]+','Bearer ***' -replace 'figu_[A-Za-z0-9._\-]+','figu_***'
    }
  }
