from pathlib import Path
import json

# template
tp = Path(r"D:\Smart\Claude-Code-Server\scripts\server\cursor-mcp-template.json")
t = json.loads(tp.read_text(encoding="utf-8"))
t["mcpServers"]["context7"] = {
    "command": "/usr/local/bin/mcp-via-xray",
    "args": ["https://mcp.context7.com/mcp"],
    "env": {"XRAY_HTTP_PROXY": "http://127.0.0.1:10809"},
}
tp.write_text(json.dumps(t, indent=2) + "\n", encoding="utf-8", newline="\n")
print("TEMPLATE_OK")

# sync.sh: context7 optional API key -> header via mcp-remote needs MCP custom headers.
# For context7, CONTEXT7_API_KEY is usually a header name itself. Keep optional headers in env as MCP_EXTRA?
# Simpler: if api_key, set header CONTEXT7_API_KEY via extending wrapper later.
# For now plain via-xray without key (works anonymously).

sync = Path(r"D:\Smart\Claude-Code-Server\scripts\server\cursor-mcp-sync.sh")
text = sync.read_text(encoding="utf-8")

# After figma block, add context7 strip url for via-xray + optional CONTEXT7 header
# Find context7_env injection that sets headers on url type - update it
old_ctx = '''context7_env = parse_env_file(home / ".config" / "cursor-mcp" / "context7.env")
api_key = context7_env.get("CONTEXT7_API_KEY")
if api_key and "context7" in merged_servers:
    ctx = merged_servers["context7"]
    if not isinstance(ctx, dict):
        ctx = {}
        merged_servers["context7"] = ctx
    headers = ctx.get("headers")
    if not isinstance(headers, dict):
        headers = {}
    headers["CONTEXT7_API_KEY"] = api_key
    ctx["headers"] = headers'''

new_ctx = '''context7_env = parse_env_file(home / ".config" / "cursor-mcp" / "context7.env")
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
        ctx["headers"] = headers'''

if old_ctx not in text:
    raise SystemExit("context7 cursor block not found")
text = text.replace(old_ctx, new_ctx, 1)

old_claude = '''    "context7": {"type": "http", "url": "https://mcp.context7.com/mcp"},
}'''
new_claude = '''    "context7": {
        "command": "/usr/local/bin/mcp-via-xray",
        "args": ["https://mcp.context7.com/mcp"],
        "env": {"XRAY_HTTP_PROXY": "http://127.0.0.1:10809"},
    },
}'''
if old_claude not in text:
    raise SystemExit("claude context7 not found")
text = text.replace(old_claude, new_claude, 1)

# claude inject: context7 with via-xray shouldn't set headers url-style only
old_inj = '''    if name == "context7" and api_key:
        entry["headers"] = {"CONTEXT7_API_KEY": api_key}
    if name == "figma":'''
new_inj = '''    if name == "context7":
        env = entry.get("env")
        if not isinstance(env, dict):
            env = {}
        env.setdefault("XRAY_HTTP_PROXY", "http://127.0.0.1:10809")
        entry["env"] = env
        entry.pop("headers", None)
        entry.pop("url", None)
        entry.pop("type", None)
    if name == "figma":'''
if old_inj not in text:
    raise SystemExit("claude context7 inject not found")
text = text.replace(old_inj, new_inj, 1)

sync.write_text(text, encoding="utf-8", newline="\n")
print("SYNC_OK")
