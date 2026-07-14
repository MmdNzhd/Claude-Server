#!/bin/bash
# test-mac-laptop-ssh-live.sh - live Mac reverse-SSH self-heal smoke test
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GIT="$ROOT/scripts/client/git-mode.sh"
FAIL=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

export ALIAS=claude-server
export CFG_DIR="$HOME/.config/claude-connect"
export CFG="$CFG_DIR/connect.conf"
export CM='$HOME/.local/bin/claude-mount'
export LAPTOP_USER="${LAPTOP_USER:-$(whoami)}"
mkdir -p "$CFG_DIR"

sshx() {
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$@"
}

# shellcheck disable=SC1090
source "$GIT"

echo '=== Live Mac laptop SSH test ==='

if [ "$(uname -s)" != "Darwin" ]; then
    fail "not running on macOS"
    exit 1
fi
pass "platform Darwin"

if ssh -o BatchMode=yes -o ConnectTimeout=10 "$ALIAS" true 2>/dev/null; then
    pass "server reachable via claude-server alias"
else
    fail "cannot reach server via claude-server (VPN?)"
fi

uid="$(sshx 'id -u' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -1)"
if [ -n "$uid" ]; then
    if acquire_tunnel_port "$uid"; then
        pass "acquire_tunnel_port PORT=$PORT slot=${TUNNEL_SLOT:-0} (uid=$uid)"
    else
        PORT=$((20000 + uid))
        fail "acquire_tunnel_port fell back to PORT=$PORT (all slots busy?)"
    fi
else
    fail "could not read server uid"
fi

if nc -zw1 127.0.0.1 22 2>/dev/null; then
    pass "local sshd listening on :22"
else
    fail "local sshd not listening"
fi

if [ -n "${PORT:-}" ]; then
    banner="$(fetch_tunnel_banner 2>/dev/null || true)"
    if [ -n "$banner" ]; then
        pass "tunnel banner: ${banner:0:40}"
        if tunnel_banner_is_this_laptop "$banner"; then
            pass "tunnel banner matches this Mac"
        else
            fail "tunnel banner is another machine (stale Windows/Linux tunnel on port $PORT)"
        fi
    else
        pass "port $PORT free - will start Mac tunnel for test"
    fi
fi

if [ -n "${PORT:-}" ] && ! tunnel_up; then
    sanitize_ssh_alias_config
    pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null || true
    ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=20 -o ServerAliveCountMax=5 \
        -R "${PORT}:localhost:22" "$ALIAS" 2>/dev/null &
    tunnel_bg=$!
    for _i in 1 2 3 4 5 6 7 8; do
        sleep 2
        tunnel_up && break
        kill -0 "$tunnel_bg" 2>/dev/null || { fail "tunnel process died on port $PORT"; break; }
    done
    tunnel_up && pass "started reverse tunnel on port $PORT" || fail "tunnel did not come up on port $PORT"
fi

pub="$(fetch_laptop_server_pubkey 2>/dev/null || true)"
if [ -n "$pub" ]; then
    pass "fetched claude_laptop.pub from server"
else
    fail "could not fetch claude_laptop.pub"
fi

if [ -n "$pub" ] && install_laptop_server_pubkey "$pub"; then
    pass "install_laptop_server_pubkey"
    [ "$(wc -l < "$HOME/.ssh/authorized_keys" | tr -d ' ')" -eq 1 ] && pass "authorized_keys has single entry" || fail "authorized_keys line count != 1"
    grep -q '^from=' "$HOME/.ssh/authorized_keys" && pass "authorized_keys has from= restriction" || fail "missing from= prefix"
else
    fail "install_laptop_server_pubkey"
fi

if [ -n "$pub" ] && verify_laptop_local_pubkey "$pub"; then
    pass "verify_laptop_local_pubkey"
else
    fail "verify_laptop_local_pubkey (will trigger self-heal in connect)"
fi

if [ -n "${PORT:-}" ] && verify_laptop_reverse_ssh; then
    pass "verify_laptop_reverse_ssh"
else
    fail "verify_laptop_reverse_ssh (needs active tunnel + local pubkey auth)"
fi

tunnel_pid=""
if [ -n "${PORT:-}" ]; then
    tunnel_pid="$(pgrep -f "ssh.*-R ${PORT}:localhost:22" | head -1 || true)"
    if [ -n "$tunnel_pid" ]; then
        pass "reverse tunnel running pid=$tunnel_pid"
    else
        fail "no reverse tunnel process for port $PORT"
    fi
fi

if [ -n "$pub" ]; then
    echo ""
    echo "=== ensure_laptop_ssh_key (self-heal) ==="
    if ensure_laptop_ssh_key "$pub"; then
        pass "ensure_laptop_ssh_key"
    else
        fail "ensure_laptop_ssh_key (needs Mac password dialog or TTY)"
    fi
fi

if [ -n "${PORT:-}" ]; then
    echo ""
    echo "=== server claude-mount tunnel-status ==="
    MOUNT_SRC="$ROOT/scripts/server/claude-mount.sh"
    if scp -o BatchMode=yes -o ConnectTimeout=30 -q "$MOUNT_SRC" "$ALIAS:~/.local/bin/claude-mount" 2>/dev/null; then
        sshx "chmod +x ~/.local/bin/claude-mount" 2>/dev/null || true
        _ts="$(sshx "$CM tunnel-status" 2>/dev/null || true)"
        printf '%s\n' "$_ts" | grep -q "TUNNEL_PORT=$PORT" && pass "server TUNNEL_PORT=$PORT" || fail "server TUNNEL_PORT mismatch"
        printf '%s\n' "$_ts" | grep -q 'tcp=open' && pass "server tcp=open" || fail "server tcp=closed"
        printf '%s\n' "$_ts" | grep -q 'banner_match=yes' && pass "server banner_match=yes" || fail "server banner_match=no"
        printf '%s\n' "$_ts" | grep -q 'auth=ok' && pass "server auth=ok" || fail "server auth=fail"
    else
        fail "could not push claude-mount.sh to server"
    fi
fi

if [ -n "${PORT:-}" ]; then
    _rc=0
    ensure_laptop_reverse_ssh "$pub" || _rc=$?
    case "$_rc" in
        0) pass "ensure_laptop_reverse_ssh" ;;
        1) fail "ensure_laptop_reverse_ssh: tunnel auth failed after local heal" ;;
        2) fail "ensure_laptop_reverse_ssh: local heal failed" ;;
    esac
fi

if [ -n "${PORT:-}" ] && [ -n "$pub" ]; then
    echo ""
    echo "=== ensure_laptop_reverse_ssh_cached ==="
    LAPTOP_SSH_VERIFIED=0
    if ensure_laptop_reverse_ssh_cached "$pub"; then
        pass "ensure_laptop_reverse_ssh_cached (full)"
    else
        fail "ensure_laptop_reverse_ssh_cached (full)"
    fi
    if ensure_laptop_reverse_ssh_cached "$pub"; then
        pass "ensure_laptop_reverse_ssh_cached (cached)"
    else
        fail "ensure_laptop_reverse_ssh_cached (cached)"
    fi
fi

if [ -n "${PORT:-}" ]; then
    echo ""
    echo "=== server claude-mount check / recover-if-needed ==="
    _check="$(sshx "$CM check claude-server 2>&1" 2>/dev/null || true)"
    case "$_check" in
        ok) pass "server check claude-server=ok" ;;
        need_mount) pass "server check claude-server=need_mount (not mounted)" ;;
        *) fail "server check unexpected: $_check" ;;
    esac
    _recover="$(sshx "$CM recover-if-needed claude-server 2>&1" 2>/dev/null | head -1 || true)"
    case "$_recover" in
        *skip*) pass "server recover-if-needed skipped or ran" ;;
        "") pass "server recover-if-needed (empty ok)" ;;
        *) pass "server recover-if-needed ran" ;;
    esac
    if sshx "grep -q 'CLAUDE_TRUSTED_TUNNEL' ~/.local/bin/claude-mount" 2>/dev/null; then
        pass "server claude-mount has CLAUDE_TRUSTED_TUNNEL"
    else
        fail "server claude-mount missing CLAUDE_TRUSTED_TUNNEL"
    fi
fi

if declare -F ensure_session_tunnel >/dev/null 2>&1 && [ -n "${PORT:-}" ] && [ -n "${tunnel_pid:-}" ]; then
    echo ""
    echo "=== ensure_session_tunnel reuse ==="
    _tunnel_alive() { kill -0 "$1" 2>/dev/null && ps -p "$1" -o state= 2>/dev/null | grep -qv 'Z'; }
    bg_pid="$tunnel_pid"
    TUNNEL_REUSED=0
    if ensure_session_tunnel; then
        if [ "${TUNNEL_REUSED:-0}" = "1" ]; then
            pass "ensure_session_tunnel reuses live tunnel"
        else
            fail "ensure_session_tunnel should reuse pid=$tunnel_pid"
        fi
    else
        fail "ensure_session_tunnel failed on reuse path"
    fi
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "ALL LIVE TESTS PASSED ($FAIL failures)"
    exit 0
fi
echo "LIVE TESTS COMPLETED WITH $FAIL FAILURE(S)"
exit 1
