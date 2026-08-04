#!/usr/bin/env bash
# Forward server 127.0.0.1:FORWARD -> laptop 127.0.0.1:LOCAL via reverse tunnel.
# Usage: windows-mcp-forward [start|status|stop]
# No-op (exit 0) when ~/.config/windows-mcp/env is missing (Mac / unused).
set -euo pipefail

ENVF="${HOME}/.config/windows-mcp/env"
CMD="${1:-start}"

if [ ! -f "$ENVF" ]; then
  echo "windows-mcp-forward: no $ENVF (skip)"
  exit 0
fi

# shellcheck disable=SC1090
source "$ENVF"
CONF="${HOME}/.claude-connect.conf"
if [ ! -f "$CONF" ]; then
  echo "windows-mcp-forward: missing $CONF (connect first)" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONF"
KEY="${HOME}/.ssh/claude_laptop"
# Default must be per-UID, NOT a shared literal: this forward binds 127.0.0.1:$FPORT
# server-wide (single network namespace). A fixed 18000 for every user meant only the
# first connected user could ever bind it; everyone else either got ECONNREFUSED (no
# one holds it) or silently rode another user's tunnel (whoever holds it already).
# ~/.config/windows-mcp/env normally pins the exact value the laptop computed the same
# way (see Sync-WindowsMcpAuthToServer in windows-mcp-laptop.ps1); this is just the
# fallback for a stale/missing env file.
_default_wmcp_port() {
  local uid base
  uid="$(id -u)"
  if [ "$uid" -ge 1000 ]; then
    base=$((28000 + uid - 1000))
  else
    base=18000
  fi
  if [ "$base" -gt 65535 ]; then base=18000; fi
  echo "$base"
}
FPORT="${WINDOWS_MCP_FORWARD_PORT:-$(_default_wmcp_port)}"
# Default local port must match windows-mcp-laptop.ps1 (18765). Do NOT use 8000:
# Hyper-V/WSL on Windows often reserves 7916-8015 (WinError 10013 on bind).
LPORT="${WINDOWS_MCP_LOCAL_PORT:-18765}"
TUNNEL_PORT="${TUNNEL_PORT:-}"
LAPTOP_USER="${LAPTOP_USER:-}"

if [ -z "${TUNNEL_PORT}" ] || [ -z "${LAPTOP_USER}" ]; then
  echo "windows-mcp-forward: TUNNEL_PORT/LAPTOP_USER unset in connect conf" >&2
  exit 1
fi

_listening() {
  ss -ltn "( sport = :$FPORT )" 2>/dev/null | grep -q ":$FPORT"
}

_listener_pids() {
  # PIDs holding 127.0.0.1:FPORT — includes ControlMaster muxes whose argv
  # no longer shows -L (so pkill -f on the forward string misses them).
  ss -ltnp "( sport = :$FPORT )" 2>/dev/null \
    | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' \
    | sort -u
}

_stop() {
  # Prefer killing our dedicated forward argv (ControlMaster=no below). Fall
  # back to FPORT holders only when they look like an ssh forward — never
  # blindly kill laptop-exec's shared ControlMaster mux.
  pkill -f "ssh.*-L 127.0.0.1:${FPORT}:127.0.0.1:" 2>/dev/null || true
  local pid cmd
  for pid in $(_listener_pids); do
    cmd="$(tr '\0' ' ' </proc/$pid/cmdline 2>/dev/null || true)"
    case "$cmd" in
      *"-L 127.0.0.1:${FPORT}:127.0.0.1:"*) kill "$pid" 2>/dev/null || true ;;
    esac
  done
  sleep 0.3
}

# Normalize curl http_code: never append via `|| echo 000` (concat → 000000).
_wmcp_http() {
  local c
  c=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${FPORT}/mcp" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H "Authorization: Bearer ${WINDOWS_MCP_AUTH_KEY}" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"wmcp-fwd","version":"0"}}}' \
    --max-time 3 2>/dev/null || true)
  c=$(printf '%s' "$c" | tr -dc '0-9')
  c=$(printf '%s' "$c" | sed 's/.*\([0-9]\{3\}\)$/\1/')
  case "$c" in
    [0-9][0-9][0-9]) printf '%s' "$c" ;;
    *) printf '000' ;;
  esac
}

case "$CMD" in
  status)
    if _listening; then
      echo "windows-mcp-forward: UP 127.0.0.1:${FPORT} -> laptop:${LPORT} (tunnel ${TUNNEL_PORT})"
      exit 0
    fi
    echo "windows-mcp-forward: DOWN"
    exit 1
    ;;
  stop)
    _stop
    echo "windows-mcp-forward: stopped"
    exit 0
    ;;
  start|"")
    # If a dedicated forward already targets the current LPORT, leave it.
    # Parallel Connect: do NOT _stop on the first non-200 — MCP cold-start and peer
    # probes race; killing a live -L drops everyone to WMCP_PROBE=000 (e2e ×6).
    # ControlMaster=no: keep this off laptop-exec's shared mux.
    if _listening && pgrep -af "ssh.*-L 127.0.0.1:${FPORT}:127.0.0.1:${LPORT}" >/dev/null 2>&1; then
      if [ -n "${WINDOWS_MCP_AUTH_KEY:-}" ]; then
        _code=000
        for _t in 1 2 3 4 5; do
          _code="$(_wmcp_http)"
          [ "$_code" = "200" ] && break
          sleep 0.6
        done
        if [ "$_code" = "200" ]; then
          echo "windows-mcp-forward: already up on $FPORT -> laptop:$LPORT (http=200)"
          exit 0
        fi
        # Forward SSH is up but MCP not ready yet — leave the -L; caller retries probe.
        echo "windows-mcp-forward: leave live forward on $FPORT (http=$_code, no_stop)"
        exit 0
      fi
      echo "windows-mcp-forward: already up on $FPORT -> laptop:$LPORT"
      exit 0
    fi
    if _listening && [ -n "${WINDOWS_MCP_AUTH_KEY:-}" ]; then
      _code=000
      for _t in 1 2 3 4 5; do
        _code="$(_wmcp_http)"
        [ "$_code" = "200" ] && break
        sleep 0.6
      done
      if [ "$_code" = "200" ]; then
        echo "windows-mcp-forward: already healthy on $FPORT (http=200, leave live session)"
        exit 0
      fi
      # Foreign/stale holder without matching argv — only then recreate.
      echo "windows-mcp-forward: FPORT up but unhealthy http=$_code; recreating" >&2
    fi
    _stop
    if _listening; then
      echo "windows-mcp-forward: FPORT $FPORT still held after stop (not our forward); cannot bind" >&2
      exit 1
    fi
    ssh -f -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
      -o StrictHostKeyChecking=accept-new \
      -o IdentitiesOnly=yes \
      -o ControlMaster=no -o ControlPath=none \
      -i "$KEY" \
      -L "127.0.0.1:${FPORT}:127.0.0.1:${LPORT}" \
      -p "$TUNNEL_PORT" "${LAPTOP_USER}@127.0.0.1"
    echo "windows-mcp-forward: UP 127.0.0.1:${FPORT} -> laptop:${LPORT}"
    exit 0
    ;;
  *)
    echo "usage: windows-mcp-forward [start|status|stop]" >&2
    exit 2
    ;;
esac
