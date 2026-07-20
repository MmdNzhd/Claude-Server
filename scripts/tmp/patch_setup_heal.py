from pathlib import Path
path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\laptop-exec-setup.sh")
text = path.read_text(encoding="utf-8")
if "claude-self-heal" in text and "GOLDEN_HEAL" in text:
    print('setup already has heal install')
else:
    # add golden path + install in _ensure_user
    if "GOLDEN_HEAL=" not in text:
        text = text.replace(
            'GOLDEN_BIN="/usr/local/bin/laptop-exec"',
            'GOLDEN_BIN="/usr/local/bin/laptop-exec"\nGOLDEN_HEAL="/usr/local/bin/claude-self-heal"',
            1,
        )
    old = '''    _ensure_user_hooks
    _ensure_cursor_git_off
}
'''
    new = '''    _ensure_user_hooks
    _ensure_cursor_git_off
    if [ -x "$GOLDEN_HEAL" ]; then
        install -m 755 "$GOLDEN_HEAL" "$HOME/.local/bin/claude-self-heal"
        "$HOME/.local/bin/claude-self-heal" --quiet 2>/dev/null || true
    fi
}
'''
    if old not in text:
        raise SystemExit('ensure_user end not found')
    text = text.replace(old, new, 1)
    path.write_text(text, encoding='utf-8', newline='\n')
    print('setup patched')
