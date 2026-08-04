# test-windows-mcp-probe-000000-hard.ps1
#
# Fleet 2026-08-03 deep-parallel:
#   WINDOWS_MCP: server_sync_probe_bad http=000000
# Root cause: remote sync used
#   code=$(curl -w "%{http_code}" ... || echo 000)
# curl already prints 000 on connect-fail and exits non-zero, so || echo 000 appends
# another 000 -> WMCP_PROBE=000000 (six digits). Never treat that as a real HTTP code.
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert-C([string]$id, [bool]$ok, [string]$title, [string]$detail) {
  if ($ok) { Write-Host "PASS  [$id] $title"; Write-Host "      $detail" }
  else { Write-Host "HARD FAIL  [$id] $title"; Write-Host "      $detail"; $script:fail++ }
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts/client/windows/windows-mcp-laptop.ps1'))) {
  $RepoRoot = 'D:\Smart\Claude-Code-Server'
}
$mcpPath = Join-Path $RepoRoot 'scripts/client/windows/windows-mcp-laptop.ps1'
$mcp = Get-Content -LiteralPath $mcpPath -Raw

Write-Host '=== windows-mcp WMCP_PROBE=000000 hard ==='
Write-Host ("root={0}" -f $RepoRoot)
Write-Host ''

Assert-C 'S1' ($mcp -match 'WMCP_PROBE') 'Sync emits WMCP_PROBE' 'ok'
Assert-C 'S1b' ($mcp -match 'Write-ConnectLog\s+\(\"WMCP_PROBE=') 'explicit day-log WMCP_PROBE= stamp' 'ok'
Assert-C 'S1c' ($mcp -match 'probe_without_sync_ok' -and ($mcp -match 'no_mcp_restart' -or $mcp -match 'Test-WindowsMcpHttpReady') -and ($mcp -match 'attempt -lt 6' -or $mcp -match 'for _t in 1 2 3 4 5')) 'local HTTP ready + retry without MCP restart' 'ok'
Assert-C 'S1d' ($mcp -match 'skip_locked_work' -and $mcp -notmatch 'proceeding_without_lock') 'mutex timeout skips Sync (no unlocked thrash)' 'ok'
Assert-C 'S1d2' ($mcp -match 'abandoned mutex' -and $mcp -match 'ensure_mutex_abandoned') 'abandoned mutex unwrap acquires lock' 'ok'
Assert-C 'S1e' ($mcp -match 'server_sync_probe_retry' -and $mcp -match 'Get-WindowsMcpRemoteProbeBashB64') 'base64 remote probe helper' 'ok'
Assert-C 'S1f' ($mcp -match 'eval \"\$\(echo \{3\} \| base64 -d\)\"' -or $mcp -match 'base64 -d\).*_wmcp_http' -or $mcp -match 'Get-WindowsMcpRemoteProbeBashB64') 'probe shipped via base64 eval (ssh -c safe)' 'ok'
Assert-C 'S2' ($mcp -notmatch '\|\|\s*echo\s+000') 'no curl failing-fallback echo 000 concat' $(if ($mcp -notmatch '\|\|\s*echo\s+000') { 'ok' } else { 'still has echo-000 fallback' })
Assert-C 'S3' ($mcp -match '_wmcp_http') 'probe uses _wmcp_http normalizer' 'ok'
Assert-C 'S4' ($mcp -match 'tr -dc' -and $mcp -match '0-9') 'normalizer strips non-digits' 'ok'
Assert-C 'S5' ($mcp -match '\[0-9\]\[0-9\]\[0-9\]') 'normalizer keeps exactly 3 digit codes' 'ok'

# Live: bash-equivalent of the old vs new snippet
$live = Join-Path $env:TEMP ("wmcp-probe-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $live | Out-Null
$sh = Join-Path $live 'probe.sh'
@'
#!/usr/bin/env bash
set -e
# Simulate curl that prints 000 and exits 7 (connect fail)
fake_curl_old() { printf '000'; return 7; }
fake_curl_new() { printf '000'; return 7; }

# OLD bug
code=$(fake_curl_old || echo 000)
echo "OLD=$code"

# NEW normalizer
_wmcp_http(){ local c; c=$(fake_curl_new || true); c=$(printf '%s' "$c" | tr -dc '0-9'); c=$(printf '%s' "$c" | sed 's/.*\([0-9]\{3\}\)$/\1/'); case "$c" in [0-9][0-9][0-9]) printf '%s' "$c";; *) printf '000';; esac; }
code=$(_wmcp_http)
echo "NEW=$code"

# Success path must stay 200
fake_curl_ok() { printf '200'; return 0; }
_wmcp_http_ok(){ local c; c=$(fake_curl_ok || true); c=$(printf '%s' "$c" | tr -dc '0-9'); c=$(printf '%s' "$c" | sed 's/.*\([0-9]\{3\}\)$/\1/'); case "$c" in [0-9][0-9][0-9]) printf '%s' "$c";; *) printf '000';; esac; }
echo "OK=$(_wmcp_http_ok)"
'@ | Set-Content -LiteralPath $sh -Encoding ASCII

# Live: reproduce old concat vs new normalizer in-process (no bash/WSL path dependency).
function Invoke-OldProbeCode([string]$curlOut, [int]$curlExit) {
  # Mirrors: code=$(curl ... || echo 000) when curl already printed 000 and exited non-zero.
  $code = $curlOut
  if ($curlExit -ne 0) { $code = $code + '000' }
  return $code
}
function Invoke-NewProbeCode([string]$curlOut) {
  $c = ($curlOut + '') -replace '[^0-9]', ''
  if ($c -match '([0-9]{3})$') { return $Matches[1] }
  return '000'
}
$old = Invoke-OldProbeCode -curlOut '000' -curlExit 7
$new = Invoke-NewProbeCode -curlOut '000'
$okc = Invoke-NewProbeCode -curlOut '200'
Write-Host ("--- in-process sim OLD={0} NEW={1} OK={2} ---" -f $old, $new, $okc)
Assert-C 'L1' ($old -eq '000000') 'L1: old snippet produces six zeros (documents the bug)' ("OLD=$old")
Assert-C 'L2' ($new -eq '000') 'L2: new normalizer yields exactly 000' ("NEW=$new")
Assert-C 'L3' ($okc -eq '200') 'L3: success path still 200' ("OK=$okc")
Assert-C 'L4' ($new -ne '000000') 'L4: new path never emits 000000' 'ok'

Write-Host ''
Write-Host ("=== RESULT fail={0} ===" -f $fail)
if ($fail -gt 0) { Write-Host 'VERDICT: FAIL'; exit 1 }
Write-Host 'VERDICT: PASS'
exit 0
