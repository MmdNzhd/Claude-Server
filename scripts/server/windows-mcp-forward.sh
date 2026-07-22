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
FPORT="${WINDOWS_MCP_FORWARD_PORT:-18000}"
LPORT="${WINDOWS_MCP_LOCAL_PORT:-8000}"
TUNNEL_PORT="${TUNNEL_PORT:-}"
LAPTOP_USER="${LAPTOP_USER:-}"

if [ -z "${TUNNEL_PORT}" ] || [ -z "${LAPTOP_USER}" ]; then
  echo "windows-mcp-forward: TUNNEL_PORT/LAPTOP_USER unset in connect conf" >&2
  exit 1
fi

_listening() {
  ss -ltn "( sport = :$FPORT )" 2>/dev/null | grep -q ":$FPORT"
}

_stop() {
  pkill -f "ssh.*-L 127.0.0.1:${FPORT}:127.0.0.1:${LPORT}" 2>/dev/null || true
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
    if _listening; then
      echo "windows-mcp-forward: already up on $FPORT"
      exit 0
    fi
    _stop
    ssh -f -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
      -o StrictHostKeyChecking=accept-new \
      -o IdentitiesOnly=yes -i "$KEY" \
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
