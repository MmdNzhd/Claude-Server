from pathlib import Path
path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-laptop-exec.sh")
text = path.read_text(encoding="utf-8")
if "claude-self-heal.sh" in text:
    print('deploy already installs self-heal')
else:
    needle = '[ -f "$SERVER_DIR/laptop-exec-setup.sh" ] && install -m 755 "$SERVER_DIR/laptop-exec-setup.sh" /usr/local/bin/laptop-exec-setup && ok "laptop-exec-setup"'
    add = needle + '\n[ -f "$SERVER_DIR/claude-self-heal.sh" ] && install -m 755 "$SERVER_DIR/claude-self-heal.sh" /usr/local/bin/claude-self-heal && ok "claude-self-heal" && sed -i \'s/\\r$//\' /usr/local/bin/claude-self-heal 2>/dev/null || true'
    if needle not in text:
        raise SystemExit('deploy needle missing')
    text = text.replace(needle, add, 1)
    # also copy to users in loop
    user_needle = '  install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec"'
    user_add = user_needle + '\n  [ -f /usr/local/bin/claude-self-heal ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/claude-self-heal "$h/.local/bin/claude-self-heal" && sed -i \'s/\\r$//\' "$h/.local/bin/claude-self-heal" 2>/dev/null || true'
    if user_needle not in text:
        raise SystemExit('user install needle missing')
    text = text.replace(user_needle, user_add, 1)
    path.write_text(text, encoding='utf-8', newline='\n')
    print('deploy patched')
