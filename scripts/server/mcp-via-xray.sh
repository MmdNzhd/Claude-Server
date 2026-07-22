#!/usr/bin/env bash
# mcp-via-xray - stdio MCP via server xray (safe cwd for multi-user)
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "mcp-via-xray: usage: mcp-via-xray <https://mcp-url> [extra mcp-remote args...]" >&2
  exit 2
fi
shift || true

PROXY="${XRAY_HTTP_PROXY:-http://127.0.0.1:10809}"
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"
export ALL_PROXY="$PROXY"
export NO_PROXY="127.0.0.1,localhost,::1"
export NODE_USE_ENV_PROXY="${NODE_USE_ENV_PROXY:-1}"

# Leave unreadable workspace cwds (other users SSHFS) before npm/npx runs.
SAFE_DIR="${HOME:-/tmp}"
if [ ! -d "$SAFE_DIR" ] || [ ! -w "$SAFE_DIR" ]; then
  SAFE_DIR=/tmp
fi
cd "$SAFE_DIR"

CACHE_DIR="${SAFE_DIR}/.npm"
mkdir -p "$CACHE_DIR"
export npm_config_cache="$CACHE_DIR"

PKG="${MCP_REMOTE_PKG:-mcp-remote@0.1.38}"
args=(-y "$PKG" "$URL")
if [ -n "${MCP_AUTH_HEADER:-}" ]; then
  args+=(--header "Authorization: ${MCP_AUTH_HEADER}")
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "mcp-via-xray: npx not found" >&2
  exit 127
fi

exec npx "${args[@]}" "$@"
