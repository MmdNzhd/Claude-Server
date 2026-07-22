#!/bin/bash
# cursor-mcp-sync - merge standard Cursor MCP pack into per-user ~/.cursor/mcp.json
#
# Usage (root):  cursor-mcp-sync --all
#                 cursor-mcp-sync --user <username>
#                 cursor-mcp-sync <username>

set -euo pipefail

[ "$EUID" -eq 0 ] || {
    echo "cursor-mcp-sync: must run as root" >&2
    exit 1
}

_resolve_template() {
    if [ -f /usr/local/lib/claude-server/cursor-mcp-template.json ]; then
        echo /usr/local/lib/claude-server/cursor-mcp-template.json
        return 0
    fi
    local _dir
    _dir="$(dirname "$(readlink -f "$0")")"
    if [ -f "$_dir/cursor-mcp-template.json" ]; then
        echo "$_dir/cursor-mcp-template.json"
        return 0
    fi
    echo "cursor-mcp-sync: cursor-mcp-template.json not found" >&2
    return 1
}

TEMPLATE="$(_resolve_template)"

_sync_user() {
    local u="$1"
    local home="/home/$u"
    id "$u" &>/dev/null || {
        echo "cursor-mcp-sync: unknown user: $u" >&2
        return 1
    }
    [ -d "$home" ] || return 0

    mkdir -p "$home/.cursor" "$home/.config/cursor-mcp"
    chmod 700 "$home/.cursor" "$home/.config/cursor-mcp"

    python3 - "$u" "$home" "$TEMPLATE" <<'PY'
import copy
import json
import sys
from pathlib import Path

username = sys.argv[1]
home = Path(sys.argv[2])
template_path = Path(sys.argv[3])

with template_path.open(encoding="utf-8") as fh:
    template = json.load(fh)

pack = template.get("mcpServers") or {}
if not isinstance(pack, dict):
    raise SystemExit("cursor-mcp-sync: template mcpServers must be an object")

mcp_path = home / ".cursor" / "mcp.json"
if mcp_path.exists():
    with mcp_path.open(encoding="utf-8") as fh:
        existing = json.load(fh)
else:
    existing = {}

if not isinstance(existing, dict):
    existing = {}

merged_servers = {}
existing_servers = existing.get("mcpServers")
if not isinstance(existing_servers, dict):
    existing_servers = {}

pack_keys = set(pack.keys())
for name, cfg in existing_servers.items():
    if name not in pack_keys:
        merged_servers[name] = copy.deepcopy(cfg)

for name, cfg in pack.items():
    merged_servers[name] = copy.deepcopy(cfg)

def parse_env_file(path: Path) -> dict:
    if not path.is_file():
        return {}
    out = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        out[key] = value
    return out

context7_env = parse_env_file(home / ".config" / "cursor-mcp" / "context7.env")
api_key = context7_env.get("CONTEXT7_API_KEY")
if "context7" in merged_servers:
    ctx = merged_servers["context7"]
    if not isinstance(ctx, dict):
        ctx = {}
        merged_servers["context7"] = ctx
    if ctx.get("command") == "/usr/local/bin/mcp-via-xray" or "mcp-via-xray" in str(ctx.get("command", "")):
        ctx.pop("url", None)
        ctx.pop("type", None)
        ctx.pop("headers", None)
        env = ctx.get("env")
        if not isinstance(env, dict):
            env = {}
        env.setdefault("XRAY_HTTP_PROXY", "http://127.0.0.1:10809")
        # Optional: Context7 accepts API key as header; mcp-via-xray only wires Authorization today.
        # Anonymous tier works without key.
        ctx["env"] = env
    elif api_key:
        headers = ctx.get("headers")
        if not isinstance(headers, dict):
            headers = {}
        headers["CONTEXT7_API_KEY"] = api_key
        ctx["headers"] = headers

# Per-user override, else server golden (never bake passwords into git templates)
sql_env = parse_env_file(home / ".config" / "cursor-mcp" / "sqlserver.env")
if not sql_env:
    sql_env = parse_env_file(Path("/etc/claude-code/sqlserver.env"))
if "sqlserver" in merged_servers:
    sql = merged_servers["sqlserver"]
    if not isinstance(sql, dict):
        sql = {}
        merged_servers["sqlserver"] = sql
    if sql_env:
        env = {k: v for k, v in sql_env.items() if k.startswith("SQLSERVER_")}
        if env:
            sql["env"] = env
        else:
            sql.pop("env", None)
    else:
        sql.pop("env", None)


# Figma OAuth access token (golden): /etc/claude-code/figma-mcp.env
# Per-user override: ~/.config/cursor-mcp/figma-mcp.env
# Token type is OAuth "figu_..." (not PAT figd_). Injected as MCP_AUTH_HEADER for mcp-via-xray.
figma_env = parse_env_file(Path("/etc/claude-code/figma-mcp.env"))
user_figma_env = parse_env_file(home / ".config" / "cursor-mcp" / "figma-mcp.env")
if user_figma_env:
    figma_env = {**figma_env, **user_figma_env}
figma_token = (
    figma_env.get("FIGMA_MCP_ACCESS_TOKEN")
    or figma_env.get("FIGMA_ACCESS_TOKEN")
    or ""
).strip()
if "figma" in merged_servers:
    figma = merged_servers["figma"]
    if not isinstance(figma, dict):
        figma = {}
        merged_servers["figma"] = figma
    # Prefer server-side stdio via mcp-via-xray (xray HTTP). Strip legacy url/headers.
    if figma.get("command") == "/usr/local/bin/mcp-via-xray" or "mcp-via-xray" in str(figma.get("command", "")):
        figma.pop("url", None)
        figma.pop("type", None)
        figma.pop("headers", None)
        env = figma.get("env")
        if not isinstance(env, dict):
            env = {}
        env.setdefault("XRAY_HTTP_PROXY", "http://127.0.0.1:10809")
        if figma_token:
            env["MCP_AUTH_HEADER"] = f"Bearer {figma_token}"
        else:
            env.pop("MCP_AUTH_HEADER", None)
        figma["env"] = env
    else:
        # Legacy HTTP MCP (client-side) — keep Bearer headers if present
        headers = figma.get("headers")
        if not isinstance(headers, dict):
            headers = {}
        if figma_token:
            headers["Authorization"] = f"Bearer {figma_token}"
            figma["headers"] = headers
        else:
            headers.pop("Authorization", None)
            if headers:
                figma["headers"] = headers
            else:
                figma.pop("headers", None)


# Knowledge graph memory MCP — per-user file (not shared across accounts)
if "memory" in merged_servers:
    mem = merged_servers["memory"]
    if not isinstance(mem, dict):
        mem = {}
        merged_servers["memory"] = mem
    env = mem.get("env")
    if not isinstance(env, dict):
        env = {}
    env.setdefault("MEMORY_FILE_PATH", str(home / ".cursor" / "mcp-memory.jsonl"))
    mem["env"] = env

existing["mcpServers"] = merged_servers

mcp_path.parent.mkdir(parents=True, exist_ok=True)
with mcp_path.open("w", encoding="utf-8") as fh:
    json.dump(existing, fh, indent=2)
    fh.write("\n")

mcp_path.chmod(0o600)
PY

    chown "$u:$u" "$home/.cursor/mcp.json"

    # Also merge Claude Code HTTP MCP (figma/context7) into existing settings.json without full overwrite
    if [ -f "$home/.claude/settings.json" ]; then
        if python3 - "$u" "$home" <<'PYCLAUDE'
import copy
import json
import sys
from pathlib import Path

username = sys.argv[1]
home = Path(sys.argv[2])
settings_path = home / ".claude" / "settings.json"
try:
    with settings_path.open(encoding="utf-8") as fh:
        settings = json.load(fh)
except Exception:
    sys.exit(0)
if not isinstance(settings, dict):
    sys.exit(0)

servers = settings.get("mcpServers")
if not isinstance(servers, dict):
    servers = {}

claude_http = {
    "figma": {
        "command": "/usr/local/bin/mcp-via-xray",
        "args": ["https://mcp.figma.com/mcp"],
        "env": {"XRAY_HTTP_PROXY": "http://127.0.0.1:10809"},
    },
    "context7": {
        "command": "/usr/local/bin/mcp-via-xray",
        "args": ["https://mcp.context7.com/mcp"],
        "env": {"XRAY_HTTP_PROXY": "http://127.0.0.1:10809"},
    },
}

# Inject Context7 API key into Claude context7 if present
env_path = home / ".config" / "cursor-mcp" / "context7.env"
api_key = None
if env_path.is_file():
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k.strip() == "CONTEXT7_API_KEY":
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            api_key = v
            break

# Figma OAuth bearer (golden /etc/claude-code/figma-mcp.env, optional per-user override)
figma_env = {}
_golden_figma = Path("/etc/claude-code/figma-mcp.env")
_user_figma = home / ".config" / "cursor-mcp" / "figma-mcp.env"
for _cand in (_golden_figma, _user_figma):
    if not _cand.is_file():
        continue
    for line in _cand.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        figma_env[k] = v
figma_token = (figma_env.get("FIGMA_MCP_ACCESS_TOKEN") or figma_env.get("FIGMA_ACCESS_TOKEN") or "").strip()

for name, cfg in claude_http.items():
    entry = copy.deepcopy(cfg)
    if name == "context7":
        env = entry.get("env")
        if not isinstance(env, dict):
            env = {}
        env.setdefault("XRAY_HTTP_PROXY", "http://127.0.0.1:10809")
        entry["env"] = env
        entry.pop("headers", None)
        entry.pop("url", None)
        entry.pop("type", None)
    if name == "figma":
        env = entry.get("env")
        if not isinstance(env, dict):
            env = {}
        env.setdefault("XRAY_HTTP_PROXY", "http://127.0.0.1:10809")
        if figma_token:
            env["MCP_AUTH_HEADER"] = f"Bearer {figma_token}"
        else:
            env.pop("MCP_AUTH_HEADER", None)
        entry["env"] = env
        entry.pop("headers", None)
        entry.pop("url", None)
        entry.pop("type", None)
    servers[name] = entry

# SQL creds: per-user sqlserver.env else golden (skip empty user file)
def _load_sql_env(path: Path) -> dict:
    if not path.is_file():
        return {}
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        if k.startswith("SQLSERVER_"):
            out[k] = v
    return out

sql_env = _load_sql_env(home / ".config" / "cursor-mcp" / "sqlserver.env")
if not sql_env:
    sql_env = _load_sql_env(Path("/etc/claude-code/sqlserver.env"))

# Memory MCP (stdio) for Claude Code — same pack as Cursor
if "memory" not in servers or not isinstance(servers.get("memory"), dict):
    servers["memory"] = {
        "type": "stdio",
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-memory"],
    }
mem = copy.deepcopy(servers["memory"])
mem.setdefault("type", "stdio")
mem.setdefault("command", "npx")
mem.setdefault("args", ["-y", "@modelcontextprotocol/server-memory"])
env = mem.get("env")
if not isinstance(env, dict):
    env = {}
env.setdefault("MEMORY_FILE_PATH", str(home / ".claude" / "mcp-memory.jsonl"))
mem["env"] = env
servers["memory"] = mem

# Ensure Claude has sqlserver stdio entry (same as add-user template), then inject env
if "sqlserver" not in servers or not isinstance(servers.get("sqlserver"), dict):
    servers["sqlserver"] = {
        "type": "stdio",
        "command": "/usr/bin/mcp-sqlserver",
        "args": [],
    }
sql = copy.deepcopy(servers["sqlserver"])
sql.setdefault("type", "stdio")
sql.setdefault("command", "/usr/bin/mcp-sqlserver")
sql.setdefault("args", [])
if sql_env:
    sql["env"] = sql_env
else:
    sql.pop("env", None)
servers["sqlserver"] = sql

settings["mcpServers"] = servers
plugins = settings.get("enabledPlugins")
if not isinstance(plugins, dict):
    plugins = {}
plugins.setdefault("figma@claude-plugins-official", True)
settings["enabledPlugins"] = plugins

with settings_path.open("w", encoding="utf-8") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
settings_path.chmod(0o600)
print(f"OK-claude {username}", flush=True)
PYCLAUDE
        then
            chown "$u:$u" "$home/.claude/settings.json" 2>/dev/null || true
        else
            printf 'WARN-claude %s settings merge failed\n' "$u" >&2
        fi
    fi

    printf 'OK %s\n' "$u"
}

TARGET=""
MODE="all"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all)
            MODE="all"
            shift
            ;;
        --user)
            [ "$#" -ge 2 ] || {
                echo "cursor-mcp-sync: --user requires a username" >&2
                exit 1
            }
            MODE="user"
            TARGET="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: cursor-mcp-sync [--all | --user NAME | NAME]" >&2
            exit 0
            ;;
        --*)
            echo "cursor-mcp-sync: unknown option: $1" >&2
            exit 1
            ;;
        *)
            MODE="user"
            TARGET="$1"
            shift
            ;;
    esac
done

case "$MODE" in
    all)
        for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
            [ -d "/home/$u" ] || continue
            [ "$u" = "designer" ] && continue
            _sync_user "$u" || {
                printf 'WARN %s sync failed - continuing\n' "$u" >&2
            }
        done
        ;;
    user)
        [ -n "$TARGET" ] || {
            echo "cursor-mcp-sync: username required" >&2
            exit 1
        }
        _sync_user "$TARGET"
        ;;
esac
