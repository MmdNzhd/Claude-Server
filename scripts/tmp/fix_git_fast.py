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
    changed = any(data.get(k) != v for k, v in WANT.items())
    if changed or not os.path.isfile(path):
        data.update(WANT)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        return "wrote"
    return "ok"

# critical live users only — mount roots + known nested only (no listdir hang)
targets = [
    ("farzadb", [
        "mounts/backend", "mounts/frontend",
    ]),
    ("hosseinm", [
        "mounts/sepidz-web", "mounts/sepidz-web/Backend", "mounts/sepidz-web/Frontend",
        "mounts/frontend", "mounts/sepidzmenuonline",
    ]),
    ("hosseinb", [
        "mounts/frontend", "mounts/backend", "mounts/portal", "mounts/sima",
    ]),
    ("nimaz", [
        "mounts/frontend", "mounts/nova", "mounts/sepidzwebapp",
    ]),
]

for user, rels in targets:
    home = f"/home/{user}"
    if not os.path.isdir(home):
        continue
    print(f"=== {user}", flush=True)
    ent = pwd.getpwnam(user)
    for rel in (
        ".cursor-server/data/User/settings.json",
        ".vscode-server/data/User/settings.json",
    ):
        if os.path.isdir(os.path.join(home, rel.split("/")[0])):
            p = os.path.join(home, rel)
            st = merge_settings(p)
            try:
                os.chown(p, ent.pw_uid, ent.pw_gid)
                os.chown(os.path.dirname(p), ent.pw_uid, ent.pw_gid)
            except OSError:
                pass
            print(f"  user {rel}: {st}", flush=True)
    for rel in rels:
        root = os.path.join(home, rel)
        if not os.path.isdir(root):
            print(f"  skip missing {rel}", flush=True)
            continue
        p = os.path.join(root, ".vscode", "settings.json")
        st = merge_settings(p)
        print(f"  ws {rel}: {st}", flush=True)

# verify live mount lib + sample settings
cm = open("/usr/local/lib/claude-mount").read()
print("LIB_USER", "cursor-server/data/User/settings.json" in cm, flush=True)
for u in ("farzadb", "hosseinm", "hosseinb"):
    p = f"/home/{u}/.cursor-server/data/User/settings.json"
    j = json.load(open(p))
    print(f"VERIFY {u} git.enabled={j.get('git.enabled')} scan={j.get('git.repositoryScanMaxDepth')}", flush=True)
print("DONE", flush=True)
