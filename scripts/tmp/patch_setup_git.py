from pathlib import Path
path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\laptop-exec-setup.sh")
text = path.read_text(encoding="utf-8")
if "_ensure_cursor_git_off" in text:
    print('already has git-off helper')
else:
    helper = r'''
_ensure_cursor_git_off() {
    # GIT_MODE=off|hide: Cursor must not probe SSHFS .git (Failed to execute git).
    # Keep this in User settings only — never write workspace .vscode (pollutes laptop repos).
    local conf="$HOME/.claude-connect.conf" mode="off"
    if [ -f "$conf" ]; then
        mode="$(grep -iE '^GIT_MODE=' "$conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr '[:upper:]' '[:lower:]' | tr -d '\r\n ')"
    fi
    case "${mode:-off}" in
        server|on|yes|1|slow) return 0 ;;
    esac
    python3 - <<'PY' 2>/dev/null || true
import json, os
home = os.path.expanduser("~")
want = {
    "git.enabled": False,
    "git.autoRepositoryDetection": False,
    "git.detectSubmodules": False,
    "git.repositoryScanMaxDepth": 0,
}
for rel in (
    ".cursor-server/data/User/settings.json",
    ".vscode-server/data/User/settings.json",
):
    top = os.path.join(home, rel.split("/")[0])
    data_dir = os.path.join(home, *rel.split("/")[:2])
    if not os.path.isdir(top) or not os.path.isdir(data_dir):
        continue
    path = os.path.join(home, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
    except (OSError, json.JSONDecodeError):
        data = {}
    data.update(want)
    data.pop("git.path", None)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
PY
}

'''
    # insert before _ensure_user and call inside _ensure_user
    marker = "_ensure_user() {"
    if marker not in text:
        raise SystemExit('no _ensure_user')
    text = text.replace(marker, helper + marker, 1)
    # add call at end of _ensure_user before closing - find "_ensure_user_hooks" call and add after
    if "_ensure_user_hooks\n}" in text:
        text = text.replace("_ensure_user_hooks\n}", "_ensure_user_hooks\n    _ensure_cursor_git_off\n}", 1)
    elif "_ensure_user_hooks" in text:
        # after first _ensure_user_hooks inside _ensure_user
        idx = text.find("_ensure_user()")
        sub = text[idx:]
        sub2 = sub.replace("_ensure_user_hooks", "_ensure_user_hooks\n    _ensure_cursor_git_off", 1)
        text = text[:idx] + sub2
    else:
        raise SystemExit('could not hook _ensure_user_hooks')
    path.write_text(text, encoding='utf-8', newline='\n')
    print('laptop-exec-setup git-off patched')
assert "_ensure_cursor_git_off" in path.read_text(encoding='utf-8')
print('verify setup ok')
