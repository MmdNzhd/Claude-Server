from pathlib import Path
path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\commands\install.sh")
text = path.read_text(encoding="utf-8")
needle = '''if [ -f "$SERVER_DIR/cursor-mcp-template.json" ]; then
    mkdir -p /usr/local/lib/claude-server
    install -m 644 "$SERVER_DIR/cursor-mcp-template.json" /usr/local/lib/claude-server/cursor-mcp-template.json
    ok "cursor-mcp-template.json -> /usr/local/lib/claude-server/"
fi
if [ -f "$SERVER_DIR/cursor-mcp-sync.sh" ]; then
    mkdir -p /usr/local/lib/claude-server
    install -m 755 "$SERVER_DIR/cursor-mcp-sync.sh" /usr/local/bin/cursor-mcp-sync
    install -m 755 "$SERVER_DIR/cursor-mcp-sync.sh" /usr/local/lib/claude-server/cursor-mcp-sync.sh
    ok "cursor-mcp-sync -> /usr/local/bin/ + /usr/local/lib/claude-server/"
fi'''
insert = '''if [ -f "$SERVER_DIR/mcp-via-xray.sh" ]; then
    install -m 755 "$SERVER_DIR/mcp-via-xray.sh" /usr/local/bin/mcp-via-xray
    mkdir -p /usr/local/lib/claude-server
    install -m 755 "$SERVER_DIR/mcp-via-xray.sh" /usr/local/lib/claude-server/mcp-via-xray.sh
    ok "mcp-via-xray -> /usr/local/bin/ (server-side HTTP MCP via xray)"
fi
'''
if "mcp-via-xray.sh" in text and "install -m 755 \"$SERVER_DIR/mcp-via-xray.sh\"" in text:
    print("INSTALL_ALREADY")
else:
    if needle not in text:
        raise SystemExit("install needle not found")
    text = text.replace(needle, insert + needle, 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    print("INSTALL_PATCHED")

docs = Path(r"D:\Smart\Claude-Code-Server\docs\cursor-mcp-pack.md")
d = docs.read_text(encoding="utf-8")
marker = "## Figma via server xray (stdio)"
if marker not in d:
    d += """

## Figma via server xray (stdio)

Figma MCP is **not** reached from the laptop `http.proxy`. Cursor launches `/usr/local/bin/mcp-via-xray` on the **Linux server** (stdio), which dials `https://mcp.figma.com/mcp` through server xray HTTP `127.0.0.1:10809`. Bearer token is injected by `cursor-mcp-sync` as `MCP_AUTH_HEADER` from `/etc/claude-code/figma-mcp.env`.

After changing the pack: `sudo claude-server sync-cursor-mcp` then **Reload Window**.
"""
    docs.write_text(d, encoding="utf-8", newline="\n")
    print("DOCS_PATCHED")
else:
    print("DOCS_ALREADY")
