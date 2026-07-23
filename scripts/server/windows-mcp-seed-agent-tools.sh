#!/usr/bin/env bash
# Propagate windows-mcp Cursor agent tool descriptors into every mounts-* project cache.
# Cursor writes tools only for the window that first connects; agents in other
# workspaces then miss user-windows-mcp. This copies a canonical pack.
set -euo pipefail
CANON="${HOME}/.config/windows-mcp/agent-tools/user-windows-mcp"
if [ ! -d "$CANON/tools" ]; then
  for d in "${HOME}/.cursor/projects"/home-*-mounts-*/mcps/user-windows-mcp; do
    if [ -d "$d/tools" ]; then
      mkdir -p "${HOME}/.config/windows-mcp/agent-tools"
      rm -rf "$CANON"
      cp -a "$d" "$CANON"
      break
    fi
  done
fi
if [ ! -d "$CANON/tools" ]; then
  echo "windows-mcp-seed-agent-tools: no canonical tools yet (connect MCP once in any window)" >&2
  exit 1
fi
n=0
for mcps in "${HOME}/.cursor/projects"/home-*-mounts-*/mcps; do
  [ -d "$mcps" ] || continue
  dest="${mcps}/user-windows-mcp"
  rm -rf "$dest"
  cp -a "$CANON" "$dest"
  n=$((n+1))
done
echo "windows-mcp-seed-agent-tools: seeded ${n} project(s) ($(ls "$CANON/tools" | wc -l) tools)"
