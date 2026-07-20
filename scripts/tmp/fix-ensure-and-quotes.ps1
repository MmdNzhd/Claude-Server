$ErrorActionPreference = 'Stop'

# --- Fix ensure_session_tunnel soft-fail ---
$shPath = (Resolve-Path 'scripts/client/git-mode.sh').Path
$sh = [IO.File]::ReadAllText($shPath)
$old = @'
ensure_session_tunnel() {
    TUNNEL_REUSED=0
    if [ -n "${bg_pid:-}" ] && _tunnel_alive "$bg_pid" && tunnel_up; then
        TUNNEL_REUSED=1
        return 0
    fi
    [ -n "${bg_pid:-}" ] && kill "$bg_pid" 2>/dev/null || true
    [ -n "${bg_pid:-}" ] && [ -n "${PORT:-}" ] && clear_server_stale_tunnel_forward "$PORT" || true
    bg_pid=""
    pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null && clear_server_stale_tunnel_forward "$PORT" || true
'@
$new = @'
ensure_session_tunnel() {
    TUNNEL_REUSED=0
    if [ -n "${bg_pid:-}" ] && _tunnel_alive "$bg_pid"; then
        if tunnel_up; then
            TUNNEL_REUSED=1
            _TUNNEL_SYNC_FAIL_COUNT=0
            return 0
        fi
        # Banner miss must not kill a healthy forward (TCP still open).
        if tunnel_port_tcp_open "$PORT"; then
            connect_log "ENSURE_TUNNEL soft_fail pid=$bg_pid port=$PORT reason=banner_miss_tcp_open" 'WARN'
            TUNNEL_REUSED=1
            _TUNNEL_SYNC_FAIL_COUNT=0
            return 0
        fi
    fi
    [ -n "${bg_pid:-}" ] && kill "$bg_pid" 2>/dev/null || true
    [ -n "${bg_pid:-}" ] && [ -n "${PORT:-}" ] && clear_server_stale_tunnel_forward "$PORT" || true
    bg_pid=""
    pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null && clear_server_stale_tunnel_forward "$PORT" || true
'@
if (-not $sh.Contains($old)) { throw 'ensure_session_tunnel block not found exactly' }
# tunnel_port_tcp_open is defined AFTER ensure_session_tunnel — need to move function or use inline.
# Better: move tunnel_port_tcp_open before ensure_session_tunnel, or call after reorder.
# Check order: tunnel_port_tcp_open is at 1046, ensure at 1015. Move tcp helper above ensure.

$tcpFnMatch = [regex]::Match($sh, '(?ms)^tunnel_port_tcp_open\(\) \{.*?^\}\r?\n')
if (-not $tcpFnMatch.Success) { throw 'tunnel_port_tcp_open not found' }
$tcpFn = $tcpFnMatch.Value
$sh2 = $sh.Remove($tcpFnMatch.Index, $tcpFnMatch.Length)
# Insert tcp fn just before ensure_session_tunnel
$marker = "# Reuse live tunnel when possible; sets TUNNEL_REUSED=0|1 and bg_pid.`nensure_session_tunnel()"
$idx = $sh2.IndexOf($marker)
if ($idx -lt 0) {
    $marker = "# Reuse live tunnel when possible; sets TUNNEL_REUSED=0|1 and bg_pid.`r`nensure_session_tunnel()"
    $idx = $sh2.IndexOf($marker)
}
if ($idx -lt 0) { throw 'ensure marker not found for insert' }
$sh2 = $sh2.Insert($idx, $tcpFn + "`n")
if (-not $sh2.Contains($old)) { throw 'ensure block missing after move' }
$sh2 = $sh2.Replace($old, $new)
[IO.File]::WriteAllText($shPath, $sh2)
Write-Host 'OK ensure_session_tunnel soft-fail + moved tunnel_port_tcp_open'

# --- Diagnose curly quote test ---
$pipe = Get-Content 'scripts/client/tests/test-connect-pipeline.ps1' -Raw
$m = [regex]::Match($pipe, "Assert \(\`$src -notmatch '([^']+)'\) `"\`$rel has no smart/curly quotes")
if ($m.Success) { Write-Host "CURLY_TEST_REGEX=$($m.Groups[1].Value)" }

$src = Get-Content 'scripts/client/windows/connect.ps1' -Raw
# Find any char > 127
$odd = New-Object System.Collections.Generic.List[string]
for ($i=0; $i -lt $src.Length; $i++) {
    $c = [int][char]$src[$i]
    if ($c -gt 127) {
        $start=[Math]::Max(0,$i-30); $len=[Math]::Min(70,$src.Length-$start)
        $odd.Add(("U+{0:X4} pos={1} ctx={2}" -f $c, $i, ($src.Substring($start,$len) -replace "[\r\n]",' ')))
        if ($odd.Count -ge 15) { break }
    }
}
Write-Host "NON_ASCII_COUNT_SAMPLE=$($odd.Count)"
$odd | ForEach-Object { Write-Host $_ }

Write-Host DONE
