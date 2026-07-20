import json, os, pwd

WANT = {
    "git.enabled": False,
    "git.autoRepositoryDetection": False,
    "git.detectSubmodules": False,
    "git.repositoryScanMaxDepth": 0,
}

def merge_settings(path: str) -> str:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
    except (OSError, json.JSONDecodeError):
        data = {}
    changed = False
    for k, v in WANT.items():
        if data.get(k) != v:
            data[k] = v
            changed = True
    if changed or not os.path.isfile(path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        return "wrote"
    return "ok"

def has_git_dir(path: str) -> bool:
    return os.path.isdir(os.path.join(path, ".git")) or os.path.isfile(os.path.join(path, ".git"))

def fix_mount(root: str):
    targets = [root]
    try:
        level1 = os.listdir(root)
    except OSError as e:
        print(f"  list_err {root}: {e}", flush=True)
        return
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
        st = merge_settings(os.path.join(t, ".vscode", "settings.json"))
        print(f"  ws {t}: {st}", flush=True)

# deploy mount lib marker check
cm = open("/usr/local/lib/claude-mount").read()
print("LIVE_HAS_USER_SETTINGS", "cursor-server/data/User/settings.json" in cm, flush=True)
print("LIVE_HAS_SCAN_DEPTH", "git.repositoryScanMaxDepth" in cm, flush=True)

# all users with home
for ent in pwd.getpwall():
    if ent.pw_uid < 1000 or ent.pw_name in ("nobody", "nfsnobody"):
        continue
    home = ent.pw_dir
    mroot = os.path.join(home, "mounts")
    if not os.path.isdir(mroot):
        continue
    print(f"=== {ent.pw_name}", flush=True)
    # user settings always
    for rel in (
        ".cursor-server/data/User/settings.json",
        ".vscode-server/data/User/settings.json",
    ):
        p = os.path.join(home, rel)
        # only if parent exists (user has used cursor/vscode remote)
        parent = os.path.dirname(p)
        if os.path.isdir(os.path.dirname(parent)) or os.path.isdir(parent):
            # create User dir if cursor-server/data exists
            data_dir = os.path.dirname(parent)
            if os.path.isdir(data_dir) or rel.startswith(".cursor-server") and os.path.isdir(os.path.join(home, ".cursor-server")):
                st = merge_settings(p)
                # fix ownership
                try:
                    os.chown(p, ent.pw_uid, ent.pw_gid)
                    os.chown(os.path.dirname(p), ent.pw_uid, ent.pw_gid)
                except OSError:
                    pass
                print(f"  user {rel}: {st}", flush=True)
    try:
        mounts = sorted(os.listdir(mroot))
    except OSError as e:
        print(f"  mounts_err {e}", flush=True)
        continue
    for mid in mounts:
        mp = os.path.join(mroot, mid)
        if os.path.isdir(mp):
            fix_mount(mp)

print("DONE", flush=True)
