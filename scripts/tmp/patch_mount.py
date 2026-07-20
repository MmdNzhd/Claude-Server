from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh")
text = p.read_text(encoding="utf-8")
if "_apply_git_scm_policy" in text:
    print("git scm already present")
else:
    old = '''_warm_sshfs_cache() {
    local lpath="$1"
    if [ -x /usr/local/bin/laptop-exec-setup ]; then
        /usr/local/bin/laptop-exec-setup --project "$lpath" 2>/dev/null || true
    fi
    (
        timeout 5 ls "$lpath/.claude/"          >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/commands/" >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.cursor/rules/"    >/dev/null 2>&1 || true
    ) &
}
'''
    new = '''# GIT_MODE=off|hide: disable Cursor SCM git over SSHFS (avoids "Failed to execute git").
# GIT_MODE=server: leave Cursor git alone.
_apply_git_scm_policy() {
    local lpath="$1"
    [ -n "$lpath" ] && [ -d "$lpath" ] || return 0
    [ "$GIT_MODE" = "server" ] && return 0
    mkdir -p "$lpath/.vscode" 2>/dev/null || return 0
    local settings="$lpath/.vscode/settings.json"
    python3 - "$settings" <<'PY' 2>/dev/null || true
import json, os, sys
path = sys.argv[1]
want = {"git.enabled": False, "git.autoRepositoryDetection": False}
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (OSError, json.JSONDecodeError):
    data = {}
changed = False
for k, v in want.items():
    if data.get(k) != v:
        data[k] = v
        changed = True
if changed or not os.path.isfile(path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\\n")
PY
}

_warm_sshfs_cache() {
    local lpath="$1"
    _apply_git_scm_policy "$lpath"
    if [ -x /usr/local/bin/laptop-exec-setup ]; then
        /usr/local/bin/laptop-exec-setup --project "$lpath" 2>/dev/null || true
    fi
    (
        timeout 5 ls "$lpath/.claude/"          >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/commands/" >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.cursor/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.vscode/"          >/dev/null 2>&1 || true
    ) &
}
'''
    if old not in text:
        raise SystemExit('warm anchor missing')
    p.write_text(text.replace(old, new), encoding='utf-8')
    print('claude-mount patched OK')
