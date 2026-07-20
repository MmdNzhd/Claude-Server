from pathlib import Path

path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh")
text = path.read_text(encoding="utf-8")
start = text.find("# GIT_MODE=off|hide: disable Cursor SCM git over SSHFS")
if start < 0:
    raise SystemExit("start marker not found")
end = text.find("\n_warm_sshfs_cache()", start)
if end < 0:
    raise SystemExit("end marker not found")

new = r'''# GIT_MODE=off|hide: disable Cursor SCM git over SSHFS (avoids "Failed to execute git").
# GIT_MODE=server: leave Cursor git alone.
# Only remote User settings (NOT workspace .vscode) so laptop-local git stays enabled.
_apply_git_scm_policy() {
    local lpath="$1"
    [ -n "$lpath" ] && [ -d "$lpath" ] || return 0
    [ "$GIT_MODE" = "server" ] && return 0
    python3 - "${HOME:-}" <<'SCM_PY' 2>/dev/null || true
import json, os, sys

home = sys.argv[1] if len(sys.argv) > 1 else ""
if not home:
    raise SystemExit(0)
want = {
    "git.enabled": False,
    "git.autoRepositoryDetection": False,
    "git.detectSubmodules": False,
    "git.repositoryScanMaxDepth": 0,
}

def merge_settings(path: str) -> None:
    parent = os.path.dirname(path)
    # only if this remote editor profile already exists
    top = os.path.dirname(os.path.dirname(parent))  # .../data
    if not os.path.isdir(top):
        return
    os.makedirs(parent, exist_ok=True)
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
            f.write("\n")

for rel in (
    ".cursor-server/data/User/settings.json",
    ".vscode-server/data/User/settings.json",
):
    merge_settings(os.path.join(home, rel))
SCM_PY
}

'''

path.write_text(text[:start] + new + text[end+1:], encoding="utf-8", newline="\n")
print("patched user-only ok")
t2 = path.read_text(encoding="utf-8")
assert "Only remote User settings" in t2
assert "cursor-server/data/User/settings.json" in t2
assert ".vscode/settings.json" not in t2[start:start+2500] or "NOT workspace" in t2
print("ok")
