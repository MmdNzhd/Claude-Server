from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\server\claude-automount.sh')
c = p.read_text(encoding='utf-8')
c = c.replace('\r\n','\n').replace('\r','\n')
needle = '# Only mount the project connect.bat selected (never mount all projects on login)\nif [ -n "$ACTIVE_MOUNT" ]; then\n    "$MOUNT_BIN" up "$ACTIVE_MOUNT" 2>/dev/null || true\n    mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true\n    touch "$STAMP" 2>/dev/null || true\nfi\n'
insert = '''# Infer ACTIVE_MOUNT when connect left it empty but tunnel is up (Cursor edge case).
LAST_ACTIVE="$HOME/.cache/claude-last-active-mount"
if [ -z "${ACTIVE_MOUNT:-}" ]; then
    if [ -f "$LAST_ACTIVE" ]; then
        ACTIVE_MOUNT="$(tr -d '\\r\\n' < "$LAST_ACTIVE" 2>/dev/null || true)"
    fi
    if [ -z "${ACTIVE_MOUNT:-}" ] && [ -d "$CONF_DIR" ]; then
        for _c in "$CONF_DIR"/*.conf; do
            [ -f "$_c" ] || continue
            _id=""
            while IFS='=' read -r _k _v; do
                _v="${_v#\\"}"; _v="${_v%\\"}"
                [ "$_k" = "id" ] && _id="$_v"
            done < "$_c"
            if [ -n "$_id" ]; then ACTIVE_MOUNT="$_id"; break; fi
        done
    fi
    if [ -n "${ACTIVE_MOUNT:-}" ] && [ -f "$CONNECT_CONF" ]; then
        if grep -qiE '^ACTIVE_MOUNT=' "$CONNECT_CONF" 2>/dev/null; then
            sed -i "s/^ACTIVE_MOUNT=.*/ACTIVE_MOUNT=$ACTIVE_MOUNT/I" "$CONNECT_CONF" 2>/dev/null || true
        else
            printf '\\nACTIVE_MOUNT=%s\\n' "$ACTIVE_MOUNT" >> "$CONNECT_CONF"
        fi
    fi
fi

# Only mount the project connect.bat selected (never mount all projects on login)
if [ -n "$ACTIVE_MOUNT" ]; then
    "$MOUNT_BIN" up "$ACTIVE_MOUNT" 2>/dev/null || true
    mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true
    touch "$STAMP" 2>/dev/null || true
    mkdir -p "$(dirname "$LAST_ACTIVE")" 2>/dev/null || true
    printf '%s\\n' "$ACTIVE_MOUNT" > "$LAST_ACTIVE" 2>/dev/null || true
fi
'''
# Fix the insert - I over-escaped. Rewrite insert cleanly.
insert = """# Infer ACTIVE_MOUNT when connect left it empty but tunnel is up (Cursor edge case).
LAST_ACTIVE=\"$HOME/.cache/claude-last-active-mount\"
if [ -z \"${ACTIVE_MOUNT:-}\" ]; then
    if [ -f \"$LAST_ACTIVE\" ]; then
        ACTIVE_MOUNT=\"$(tr -d '\\r\\n' < \"$LAST_ACTIVE\" 2>/dev/null || true)\"
    fi
    if [ -z \"${ACTIVE_MOUNT:-}\" ] && [ -d \"$CONF_DIR\" ]; then
        for _c in \"$CONF_DIR\"/*.conf; do
            [ -f \"$_c\" ] || continue
            _id=\"\"
            while IFS='=' read -r _k _v; do
                _v=\"${_v#\\\"}\"; _v=\"${_v%\\\"}\"
                [ \"$_k\" = \"id\" ] && _id=\"$_v\"
            done < \"$_c\"
            if [ -n \"$_id\" ]; then ACTIVE_MOUNT=\"$_id\"; break; fi
        done
    fi
    if [ -n \"${ACTIVE_MOUNT:-}\" ] && [ -f \"$CONNECT_CONF\" ]; then
        if grep -qiE '^ACTIVE_MOUNT=' \"$CONNECT_CONF\" 2>/dev/null; then
            sed -i \"s/^ACTIVE_MOUNT=.*/ACTIVE_MOUNT=$ACTIVE_MOUNT/I\" \"$CONNECT_CONF\" 2>/dev/null || true
        else
            printf '\\nACTIVE_MOUNT=%s\\n' \"$ACTIVE_MOUNT\" >> \"$CONNECT_CONF\"
        fi
    fi
fi

# Only mount the project connect.bat selected (never mount all projects on login)
if [ -n \"$ACTIVE_MOUNT\" ]; then
    \"$MOUNT_BIN\" up \"$ACTIVE_MOUNT\" 2>/dev/null || true
    mkdir -p \"$(dirname \"$STAMP\")\" 2>/dev/null || true
    touch \"$STAMP\" 2>/dev/null || true
    mkdir -p \"$(dirname \"$LAST_ACTIVE\")\" 2>/dev/null || true
    printf '%s\\n' \"$ACTIVE_MOUNT\" > \"$LAST_ACTIVE\" 2>/dev/null || true
fi
"""
if 'claude-last-active-mount' in c:
    print('automount already has last-active')
else:
    if needle not in c:
        raise SystemExit('needle not found in automount')
    c = c.replace(needle, insert)
    p.write_bytes(c.encode('utf-8'))
    print('patched automount ACTIVE_MOUNT infer')
print('VSCODE_RESOLVING', 'VSCODE_RESOLVING_ENVIRONMENT' in c)
print('last-active', 'claude-last-active-mount' in c)
