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
# Workspace + nested git roots + remote User settings so Cursor never probes SSHFS .git.
_apply_git_scm_policy() {
    local lpath="$1"
    [ -n "$lpath" ] && [ -d "$lpath" ] || return 0
    [ "$GIT_MODE" = "server" ] && return 0
    python3 - "$lpath" "${HOME:-}" <<'SCM_PY' 2>/dev/null || true
import json, os, sys

root = sys.argv[1]
home = sys.argv[2] if len(sys.argv) > 2 else ""
want = {
    "git.enabled": False,
    "git.autoRepositoryDetection": False,
    "git.detectSubmodules": False,
    "git.repositoryScanMaxDepth": 0,
}

def merge_settings(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
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

def has_git_dir(path: str) -> bool:
    return os.path.isdir(os.path.join(path, ".git")) or os.path.isfile(os.path.join(path, ".git"))

targets = [root]
try:
    level1 = os.listdir(root)
except OSError:
    level1 = []
for name in level1:
    if name.startswith("."):
        continue
    p1 = os.path.join(root, name)
    if not os.path.isdir(p1):
        continue
    if has_git_dir(p1):
        targets.append(p1)
    try:
        level2 = os.listdir(p1)
    except OSError:
        continue
    for name2 in level2:
        if name2.startswith("."):
            continue
        p2 = os.path.join(p1, name2)
        if os.path.isdir(p2) and has_git_dir(p2):
            targets.append(p2)

seen = set()
for t in targets:
    if t in seen:
        continue
    seen.add(t)
    merge_settings(os.path.join(t, ".vscode", "settings.json"))

if home:
    for rel in (
        ".cursor-server/data/User/settings.json",
        ".vscode-server/data/User/settings.json",
    ):
        merge_settings(os.path.join(home, rel))
SCM_PY
}

'''

path.write_text(text[:start] + new + text[end+1:], encoding="utf-8", newline="\n")
print("patched ok")
t2 = path.read_text(encoding="utf-8")
assert "git.repositoryScanMaxDepth" in t2
assert "cursor-server/data/User/settings.json" in t2
print("verify ok calls=", t2.count("_apply_git_scm_policy"))
