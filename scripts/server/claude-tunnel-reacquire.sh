#!/bin/bash
# claude-tunnel-reacquire.sh — shared helpers for TUNNEL_PORT ownership + reacquire.
# Sourced by claude-self-heal and claude-watchdog.
# Install: /usr/local/lib/claude-server/claude-tunnel-reacquire.sh (mode 644)
#
# Contract:
#   tunnel_block_base [uid]
#   tunnel_port_tcp_open <port>
#   tunnel_hostkey_fps <port>          # prints all SHA256:/MD5: lines
#   tunnel_hostkey_matches_pin <port> <pin>
#   tunnel_auth_owned <port>           # uses LAPTOP_USER + HOME/.ssh/claude_laptop + LAPTOP_OS
#   rewrite_conf_tunnel_ports <port>
#   reacquire_tunnel_port_into_conf    # lowest owned live slot → conf
#   tunnel_up_effective                # conf port up OR any owned block port up
#
# Auth-primary ownership: never clear solely on head-1 hostkey mismatch.
# Hostkey match = pin equals ANY scanned FP (not head -1 alone).

# Avoid re-sourcing pollution
: "${_CLAUDE_TUNNEL_REACQUIRE_LOADED:=0}"
[ "$_CLAUDE_TUNNEL_REACQUIRE_LOADED" = "1" ] && return 0 2>/dev/null || true
_CLAUDE_TUNNEL_REACQUIRE_LOADED=1

tunnel_block_base() {
    local uid="${1:-}"
    if [ -z "$uid" ]; then
        uid="$(id -u 2>/dev/null || echo 0)"
    fi
    if [ "$uid" -ge 1000 ] 2>/dev/null; then
        echo $((20000 + (uid - 1000) * 10))
    else
        echo 20020
    fi
}

tunnel_port_tcp_open() {
    local port="${1:-}"
    [ -n "$port" ] || return 1
    timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/${port}" 2>/dev/null
}

# Print all fingerprints from multi-type keyscan (RSA/ECDSA/ED25519).
# Never use head -1 alone for ownership decisions.
tunnel_hostkey_fps() {
    local port="${1:-}"
    [ -n "$port" ] || return 1
    timeout 4 ssh-keyscan -p "$port" -T 3 -t ed25519,rsa,ecdsa 127.0.0.1 2>/dev/null \
        | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' | grep -E '^(SHA256:|MD5:)' || true
}

tunnel_hostkey_matches_pin() {
    local port="${1:-}" pin="${2:-}" fp
    [ -n "$port" ] && [ -n "$pin" ] || return 1
    while IFS= read -r fp; do
        [ -n "$fp" ] || continue
        if [ "$fp" = "$pin" ]; then
            return 0
        fi
    done < <(tunnel_hostkey_fps "$port")
    return 1
}

tunnel_auth_owned() {
    local port="${1:-}" lu="${LAPTOP_USER:-}" remote_cmd="true" os_lc home_dir
    home_dir="${HOME:-}"
    [ -n "$port" ] && [ -n "$lu" ] || return 1
    [ -n "$home_dir" ] || return 1
    [ -f "$home_dir/.ssh/claude_laptop" ] || return 1
    os_lc="$(printf '%s' "${LAPTOP_OS:-}" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n ')"
    case "$os_lc" in
        win|windows) remote_cmd="powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command exit" ;;
        mac|darwin) remote_cmd="true" ;;
        *)
            remote_cmd="powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command exit"
            ;;
    esac
    local kh="$home_dir/.ssh/known_hosts_claude_reacquire"
    touch "$kh" 2>/dev/null || true
    chmod 600 "$kh" 2>/dev/null || true
    timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=3 -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$kh" \
        -i "$home_dir/.ssh/claude_laptop" -p "$port" "${lu}@127.0.0.1" $remote_cmd >/dev/null 2>&1
}

# True if port is ours: auth OK, or (pin set and any FP matches).
tunnel_port_owned() {
    local port="${1:-}" pin="${LAPTOP_HOSTKEY_FP:-}"
    [ -n "$port" ] || return 1
    tunnel_port_tcp_open "$port" || return 1
    if tunnel_auth_owned "$port"; then
        return 0
    fi
    if [ -n "$pin" ] && tunnel_hostkey_matches_pin "$port" "$pin"; then
        return 0
    fi
    return 1
}

rewrite_conf_tunnel_ports() {
    local port="${1:-}" conf="${CONNECT_CONF:-$HOME/.claude-connect.conf}" base slot
    [ -n "$port" ] || return 1
    [ -f "$conf" ] || return 1
    base="$(tunnel_block_base)"
    slot=$((port - base))
    if [ "$slot" -lt 0 ] 2>/dev/null || [ "$slot" -gt 9 ] 2>/dev/null; then
        slot=0
    fi
    local tmp="${conf}.tmp.$$"
    grep -vE '^(TUNNEL_PORT|PORT|TUNNEL_SLOT)=' "$conf" > "$tmp" 2>/dev/null || true
    printf 'TUNNEL_PORT=%s\nPORT=%s\nTUNNEL_SLOT=%s\n' "$port" "$port" "$slot" >> "$tmp"
    mv -f "$tmp" "$conf"
    chmod 600 "$conf" 2>/dev/null || true
    TUNNEL_PORT="$port"
}

# If TUNNEL_PORT empty or dead: scan slots 0..9; prefer lowest owned live; write conf.
reacquire_tunnel_port_into_conf() {
    local base slot cand chosen="" conf="${CONNECT_CONF:-$HOME/.claude-connect.conf}"
    base="$(tunnel_block_base)"

    # If conf port already owned+up, keep it.
    if [ -n "${TUNNEL_PORT:-}" ] && tunnel_port_owned "$TUNNEL_PORT"; then
        return 0
    fi

    for slot in 0 1 2 3 4 5 6 7 8 9; do
        cand=$((base + slot))
        [ "$cand" -gt 20000 ] 2>/dev/null && [ "$cand" -le 65535 ] 2>/dev/null || continue
        if tunnel_port_owned "$cand"; then
            chosen="$cand"
            break
        fi
    done

    [ -n "$chosen" ] || return 1
    if [ -f "$conf" ]; then
        rewrite_conf_tunnel_ports "$chosen"
    else
        TUNNEL_PORT="$chosen"
    fi
    if command -v logger >/dev/null 2>&1; then
        logger -t claude-self-heal "TUNNEL_PORT_REACQUIRED port=$chosen user=${USER_NAME:-$(id -un 2>/dev/null || echo unknown)}"
    fi
    return 0
}

# Conf port TCP-up, OR any owned block port up (even when conf blank).
tunnel_up_effective() {
    local base slot cand
    if [ -n "${TUNNEL_PORT:-}" ] && tunnel_port_tcp_open "$TUNNEL_PORT"; then
        return 0
    fi
    base="$(tunnel_block_base)"
    for slot in 0 1 2 3 4 5 6 7 8 9; do
        cand=$((base + slot))
        if tunnel_port_owned "$cand"; then
            return 0
        fi
    done
    return 1
}
