from pathlib import Path
path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\claude-automount.sh")
text = path.read_text(encoding="utf-8")

# Insert self-heal early after cursor-auth, and before tunnel-down exit
if "claude-self-heal" not in text:
    needle = '''if [ -x /usr/local/bin/laptop-exec-setup ]; then
    /usr/local/bin/laptop-exec-setup --user
    /usr/local/bin/laptop-exec-setup --all-projects 2>/dev/null || true
fi
'''
    insert = needle + '''
# Full self-heal (CRLF, Cursor git-off, conf normalize, stale mounts, shim)
if [ -x /usr/local/bin/claude-self-heal ]; then
    /usr/local/bin/claude-self-heal --quiet 2>/dev/null || true
elif [ -x "$HOME/.local/bin/claude-self-heal" ]; then
    "$HOME/.local/bin/claude-self-heal" --quiet 2>/dev/null || true
fi
'''
    if needle not in text:
        raise SystemExit('automount needle not found')
    text = text.replace(needle, insert, 1)

# When tunnel down, currently exits without heal — change to heal then exit
old = '''    if [ -n "$TUNNEL_PORT" ]; then
        if ! timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null; then
            exit 0
        fi
    fi
'''
new = '''    if [ -n "$TUNNEL_PORT" ]; then
        if ! timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null; then
            # Still self-heal: unmount stale SSHFS so IO cannot hang while offline
            if [ -x /usr/local/bin/claude-self-heal ]; then
                /usr/local/bin/claude-self-heal --quiet 2>/dev/null || true
            fi
            exit 0
        fi
    fi
'''
if old not in text:
    raise SystemExit('tunnel-down block not found')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8', newline='\n')
print('automount patched')
