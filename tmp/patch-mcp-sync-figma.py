from pathlib import Path

path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\cursor-mcp-sync.sh")
text = path.read_text(encoding="utf-8")

old_cursor = '''if "figma" in merged_servers:
    figma = merged_servers["figma"]
    if not isinstance(figma, dict):
        figma = {}
        merged_servers["figma"] = figma
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
            figma.pop("headers", None)'''

new_cursor = '''if "figma" in merged_servers:
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
                figma.pop("headers", None)'''

if old_cursor not in text:
    raise SystemExit("cursor figma block not found")
text = text.replace(old_cursor, new_cursor, 1)

old_claude = '''claude_http = {
    "figma": {"type": "http", "url": "https://mcp.figma.com/mcp"},
    "context7": {"type": "http", "url": "https://mcp.context7.com/mcp"},
}'''

new_claude = '''claude_http = {
    "figma": {
        "command": "/usr/local/bin/mcp-via-xray",
        "args": ["https://mcp.figma.com/mcp"],
        "env": {"XRAY_HTTP_PROXY": "http://127.0.0.1:10809"},
    },
    "context7": {"type": "http", "url": "https://mcp.context7.com/mcp"},
}'''

if old_claude not in text:
    raise SystemExit("claude_http block not found")
text = text.replace(old_claude, new_claude, 1)

old_claude_inj = '''for name, cfg in claude_http.items():
    entry = copy.deepcopy(cfg)
    if name == "context7" and api_key:
        entry["headers"] = {"CONTEXT7_API_KEY": api_key}
    if name == "figma" and figma_token:
        entry["headers"] = {"Authorization": f"Bearer {figma_token}"}
    servers[name] = entry'''

new_claude_inj = '''for name, cfg in claude_http.items():
    entry = copy.deepcopy(cfg)
    if name == "context7" and api_key:
        entry["headers"] = {"CONTEXT7_API_KEY": api_key}
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
    servers[name] = entry'''

if old_claude_inj not in text:
    raise SystemExit("claude inject block not found")
text = text.replace(old_claude_inj, new_claude_inj, 1)

# comment update near figma token
text = text.replace(
    "# Token type is OAuth \"figu_...\" (not PAT figd_). Injected as Authorization Bearer.",
    "# Token type is OAuth \"figu_...\" (not PAT figd_). Injected as MCP_AUTH_HEADER for mcp-via-xray.",
    1,
)

path.write_text(text, encoding="utf-8", newline="\n")
print("SYNC_PATCHED")
