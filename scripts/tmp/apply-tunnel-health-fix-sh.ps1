$ErrorActionPreference = 'Stop'
$root = (Resolve-Path '.').Path

function Replace-Exact {
    param([string]$Path, [string]$Old, [string]$New, [string]$Label)
    $raw = [IO.File]::ReadAllText($Path)
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $c = $raw -replace "`r`n", "`n" -replace "`r", "`n"
    $oldN = $Old -replace "`r`n", "`n" -replace "`r", "`n"
    $newN = $New -replace "`r`n", "`n" -replace "`r", "`n"
    if ($c.IndexOf($oldN) -lt 0) { throw "pattern missing: $Label in $Path" }
    $n = 0; $i = 0
    while (($i = $c.IndexOf($oldN, $i)) -ge 0) { $n++; $i += $oldN.Length }
    if ($n -ne 1) { throw "expected 1 occurrence of $Label, found $n" }
    $c2 = $c.Replace($oldN, $newN)
    if ($nl -eq "`r`n") { $c2 = $c2 -replace "`n", "`r`n" }
    # For .sh prefer LF
    if ($Path -match '\.sh$') { $c2 = $c2 -replace "`r`n", "`n" -replace "`r", "`n" }
    [IO.File]::WriteAllText($Path, $c2)
    Write-Host "OK $Label"
}

$sh = Join-Path $root 'scripts\client\git-mode.sh'

Replace-Exact -Path $sh -Label 'tunnel_fetch_banner_raw' -Old @'
tunnel_fetch_banner_raw() {
    [ -n "${PORT:-}" ] || return 1
    sshx "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PORT} 2>/dev/null && timeout 2 nc 127.0.0.1 ${PORT} 2>/dev/null | head -1' 2>/dev/null" 2>/dev/null | tr -d '\r\n'
}
'@ -New @'
tunnel_fetch_banner_raw() {
    [ -n "${PORT:-}" ] || return 1
    # Single TCP connection — avoid /dev/tcp+nc (2 MaxStartups slots).
    sshx "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PORT} 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s \"\$line\"' 2>/dev/null" 2>/dev/null | tr -d '\r\n'
}

tunnel_tcp_open() {
    [ -n "${PORT:-}" ] || return 1
    local out
    out="$(sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PORT} 2>/dev/null' && echo open || echo closed" 2>/dev/null | tr -d '\r\n')"
    echo "$out" | grep -q 'open'
}
'@

Replace-Exact -Path $sh -Label 'tunnel_fetch_banner' -Old @'
tunnel_fetch_banner() {
    local now age_ms banner
    [ -n "${PORT:-}" ] || return 1
    if [ "$_TUNNEL_BANNER_CACHE_INVALID" -eq 0 ] && [ "$_TUNNEL_BANNER_CACHE_AT" -gt 0 ]; then
        now="$(date +%s 2>/dev/null || printf '0')"
        age_ms=$(( (now - _TUNNEL_BANNER_CACHE_AT) * 1000 ))
        if [ "$age_ms" -lt 3000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_BANNER cache hit age_ms=$age_ms banner=$_TUNNEL_BANNER_CACHE_BANNER" 'TRACE'
            fi
            printf '%s' "$_TUNNEL_BANNER_CACHE_BANNER"
            return 0
        fi
    fi
    _TUNNEL_BANNER_CACHE_INVALID=0
    banner="$(tunnel_fetch_banner_raw 2>/dev/null || true)"
    _TUNNEL_BANNER_CACHE_AT="$(date +%s 2>/dev/null || printf '0')"
    _TUNNEL_BANNER_CACHE_BANNER="$banner"
    if [ -n "$banner" ] && tunnel_banner_is_this_laptop "$banner"; then
        _TUNNEL_BANNER_CACHE_UP=1
    else
        _TUNNEL_BANNER_CACHE_UP=0
    fi
    printf '%s' "$banner"
}
'@ -New @'
tunnel_fetch_banner() {
    local now age_ms banner
    [ -n "${PORT:-}" ] || return 1
    # Positive cache only — never poison with empty banner for 3s.
    if [ "$_TUNNEL_BANNER_CACHE_INVALID" -eq 0 ] && [ "$_TUNNEL_BANNER_CACHE_AT" -gt 0 ] && [ "$_TUNNEL_BANNER_CACHE_UP" -eq 1 ]; then
        now="$(date +%s 2>/dev/null || printf '0')"
        age_ms=$(( (now - _TUNNEL_BANNER_CACHE_AT) * 1000 ))
        if [ "$age_ms" -lt 3000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_BANNER cache hit age_ms=$age_ms banner=$_TUNNEL_BANNER_CACHE_BANNER" 'TRACE'
            fi
            printf '%s' "$_TUNNEL_BANNER_CACHE_BANNER"
            return 0
        fi
    fi
    _TUNNEL_BANNER_CACHE_INVALID=0
    banner="$(tunnel_fetch_banner_raw 2>/dev/null || true)"
    case "$banner" in
        *MaxStartups*)
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_BANNER soft_fail port=$PORT reason=maxstartups" 'WARN'
            fi
            banner=""
            ;;
    esac
    if [ -n "$banner" ] && tunnel_banner_is_this_laptop "$banner"; then
        _TUNNEL_BANNER_CACHE_AT="$(date +%s 2>/dev/null || printf '0')"
        _TUNNEL_BANNER_CACHE_BANNER="$banner"
        _TUNNEL_BANNER_CACHE_UP=1
    else
        _TUNNEL_BANNER_CACHE_AT=0
        _TUNNEL_BANNER_CACHE_BANNER=""
        _TUNNEL_BANNER_CACHE_UP=0
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_BANNER miss port=$PORT banner=$banner" 'DEBUG'
        fi
    fi
    printf '%s' "$banner"
}
'@

Replace-Exact -Path $sh -Label 'tunnel_up' -Old @'
tunnel_up() {
    local banner age_ms now
    if [ "$_TUNNEL_BANNER_CACHE_INVALID" -eq 0 ] && [ "$_TUNNEL_BANNER_CACHE_AT" -gt 0 ]; then
        now="$(date +%s 2>/dev/null || printf '0')"
        age_ms=$(( (now - _TUNNEL_BANNER_CACHE_AT) * 1000 ))
        if [ "$age_ms" -lt 3000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_UP port=$PORT up=$_TUNNEL_BANNER_CACHE_UP cache=1" 'TRACE'
            fi
            [ "$_TUNNEL_BANNER_CACHE_UP" -eq 1 ]
            return
        fi
    fi
    banner="$(tunnel_fetch_banner 2>/dev/null || true)"
    [ -n "$banner" ] || return 1
    tunnel_banner_is_this_laptop "$banner"
}
'@ -New @'
tunnel_up() {
    local banner age_ms now attempt
    if [ "$_TUNNEL_BANNER_CACHE_INVALID" -eq 0 ] && [ "$_TUNNEL_BANNER_CACHE_AT" -gt 0 ] && [ "$_TUNNEL_BANNER_CACHE_UP" -eq 1 ]; then
        now="$(date +%s 2>/dev/null || printf '0')"
        age_ms=$(( (now - _TUNNEL_BANNER_CACHE_AT) * 1000 ))
        if [ "$age_ms" -lt 3000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_UP port=$PORT up=1 cache=1" 'TRACE'
            fi
            return 0
        fi
    fi
    for attempt in 1 2 3; do
        [ "$attempt" -gt 1 ] && sleep 0.25
        banner="$(tunnel_fetch_banner 2>/dev/null || true)"
        if [ -n "$banner" ] && tunnel_banner_is_this_laptop "$banner"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_UP port=$PORT up=1 attempt=$attempt" 'TRACE'
            fi
            return 0
        fi
    done
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "TUNNEL_UP port=$PORT up=0" 'TRACE'
    fi
    return 1
}
'@

Replace-Exact -Path $sh -Label 'sync_session_tunnel_forward' -Old @'
    _LAST_FORWARD_PROBE_AT="$now"
    clear_tunnel_banner_cache
    if tunnel_up; then
        probe_up=1
    else
        probe_up=0
    fi
    if [ "$probe_up" -eq 0 ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_DROP pid=$bg_pid port=$PORT reason=bg_alive_forward_dead" 'WARN'
        fi
        release_stale_tunnel_port || true
        return 1
    fi
'@ -New @'
    _LAST_FORWARD_PROBE_AT="$now"
    clear_tunnel_banner_cache
    if tunnel_up; then
        probe_up=1
    else
        probe_up=0
    fi
    if [ "$probe_up" -eq 0 ]; then
        if declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail pid=$bg_pid port=$PORT reason=banner_miss_tcp_open" 'WARN'
            fi
        else
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_DROP pid=$bg_pid port=$PORT reason=bg_alive_forward_dead" 'WARN'
            fi
            release_stale_tunnel_port || true
            return 1
        fi
    fi
'@

# Bump version
$ver = '20260717.5'
@(
  'scripts\client\windows\connect-version.txt',
  'scripts\client\mac\connect-version.txt'
) | ForEach-Object {
  $p = Join-Path $root $_
  [IO.File]::WriteAllText($p, $ver)
  Write-Host "OK version file $_ = $ver"
}

$cps = Join-Path $root 'scripts\client\windows\connect.ps1'
$raw = [IO.File]::ReadAllText($cps)
if ($raw -notmatch "ConnectVersion = '20260717\.4'") { throw 'connect.ps1 version pattern missing' }
$raw2 = $raw -replace "ConnectVersion = '20260717\.4'", "ConnectVersion = '$ver'"
[IO.File]::WriteAllText($cps, $raw2)
Write-Host 'OK connect.ps1 version'

$csh = Join-Path $root 'scripts\client\mac\connect.sh'
$raw = [IO.File]::ReadAllText($csh) -replace "`r`n","`n" -replace "`r","`n"
if ($raw -notmatch "CONNECT_VERSION='20260717\.4'") { throw 'connect.sh version pattern missing' }
$raw2 = $raw -replace "CONNECT_VERSION='20260717\.4'", "CONNECT_VERSION='$ver'"
[IO.File]::WriteAllText($csh, $raw2)
Write-Host 'OK connect.sh version'

Write-Host 'ALL_SH_OK'
