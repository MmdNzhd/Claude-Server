import json, os, pwd, stat

KEYS = ("git.enabled", "git.autoRepositoryDetection", "git.detectSubmodules", "git.repositoryScanMaxDepth")

def strip_path(p, uid, gid):
    if not os.path.isfile(p):
        return "missing"
    try:
        data = json.load(open(p, encoding="utf-8"))
    except Exception as e:
        return f"read_err:{e}"
    if not isinstance(data, dict):
        return "not_dict"
    changed = False
    for k in KEYS:
        if k in data:
            del data[k]
            changed = True
    if not changed:
        return "clean"
    # always write remaining (or {}) — never delete (SSHFS perms)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    try:
        os.chown(p, uid, gid)
    except OSError:
        pass
    return "stripped"

jobs = [
    ("farzadb", [
        "mounts/backend/.vscode/settings.json",
        "mounts/frontend/.vscode/settings.json",
    ]),
    ("hosseinm", [
        "mounts/sepidz-web/.vscode/settings.json",
        "mounts/sepidz-web/Backend/.vscode/settings.json",
        "mounts/sepidz-web/Frontend/.vscode/settings.json",
        "mounts/frontend/.vscode/settings.json",
        "mounts/sepidzmenuonline/.vscode/settings.json",
    ]),
    ("hosseinb", [
        "mounts/frontend/.vscode/settings.json",
        "mounts/backend/.vscode/settings.json",
        "mounts/portal/.vscode/settings.json",
        "mounts/sima/.vscode/settings.json",
    ]),
    ("nimaz", [
        "mounts/frontend/.vscode/settings.json",
        "mounts/nova/.vscode/settings.json",
        "mounts/sepidzwebapp/.vscode/settings.json",
    ]),
]

for user, rels in jobs:
    ent = pwd.getpwnam(user)
    print(f"=== {user}", flush=True)
    for rel in rels:
        p = os.path.join(ent.pw_dir, rel)
        # try as root first; if EACCES, note it
        try:
            st = strip_path(p, ent.pw_uid, ent.pw_gid)
        except PermissionError as e:
            st = f"perm:{e}"
        print(f"  {rel}: {st}", flush=True)

# verify user settings + live lib
cm = open("/usr/local/lib/claude-mount").read()
print("LIB", "Only remote User settings" in cm, flush=True)
for u in ("farzadb", "hosseinm", "hosseinb"):
    p = f"/home/{u}/.cursor-server/data/User/settings.json"
    j = json.load(open(p))
    assert j.get("git.enabled") is False
    print(f"OK {u} remote git.enabled=False", flush=True)
print("DONE", flush=True)
