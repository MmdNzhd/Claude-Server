#!/usr/bin/env python3
"""Fully disable Cursor remote git SCM for all users. Does NOT delete .git repos."""
import json, os, pwd, glob

WANT = {
    "git.enabled": False,
    "git.autoRepositoryDetection": False,
    "git.detectSubmodules": False,
    "git.repositoryScanMaxDepth": 0,
}
# remove any shim path we might have set
DROP_KEYS = ("git.path",)

def merge(path, uid=None, gid=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        data = json.load(open(path, encoding="utf-8"))
        if not isinstance(data, dict):
            data = {}
    except (OSError, json.JSONDecodeError):
        data = {}
    changed = False
    for k, v in WANT.items():
        if data.get(k) != v:
            data[k] = v
            changed = True
    for k in DROP_KEYS:
        if k in data:
            del data[k]
            changed = True
    if changed or not os.path.isfile(path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        if uid is not None:
            try:
                os.chown(path, uid, gid)
                os.chown(os.path.dirname(path), uid, gid)
            except OSError:
                pass
        return "wrote"
    return "ok"

# verify mount policy still disables
cm = open("/usr/local/lib/claude-mount").read()
print("POLICY_DISABLE", '"git.enabled": False' in cm or "'git.enabled': False" in cm, flush=True)
print("POLICY_USER", "Only remote User settings" in cm, flush=True)

# remove shim if installed
for p in (
    "/usr/local/bin/git-via-laptop-exec",
    "/usr/local/lib/claude-server/git-via-laptop-exec.sh",
):
    if os.path.isfile(p):
        os.remove(p)
        print("removed", p, flush=True)

n = 0
for ent in pwd.getpwall():
    if ent.pw_uid < 1000 or ent.pw_name in ("nobody", "nfsnobody"):
        continue
    home = ent.pw_dir
    if not os.path.isdir(home):
        continue
    # only users with cursor-server
    if not os.path.isdir(os.path.join(home, ".cursor-server")) and not os.path.isdir(os.path.join(home, ".vscode-server")):
        continue
    print(f"=== {ent.pw_name}", flush=True)
    for rel in (
        ".cursor-server/data/User/settings.json",
        ".vscode-server/data/User/settings.json",
    ):
        top = os.path.join(home, rel.split("/")[0])
        if not os.path.isdir(top):
            continue
        # need data dir
        data = os.path.join(home, *rel.split("/")[:2])  # .cursor-server/data
        if not os.path.isdir(data) and "cursor-server" in rel:
            continue
        if not os.path.isdir(os.path.join(home, ".vscode-server", "data")) and "vscode-server" in rel:
            continue
        p = os.path.join(home, rel)
        st = merge(p, ent.pw_uid, ent.pw_gid)
        print(f"  {rel}: {st}", flush=True)
        n += 1
    # remove per-user shim if any
    shim = os.path.join(home, ".local/bin/git-via-laptop-exec")
    if os.path.isfile(shim):
        os.remove(shim)
        print("  removed user shim", flush=True)

# verify live users
for u in ("farzadb", "hosseinm", "hosseinb", "nimaz"):
    p = f"/home/{u}/.cursor-server/data/User/settings.json"
    j = json.load(open(p))
    assert j.get("git.enabled") is False
    assert "git.path" not in j
    print(f"VERIFY {u} git.enabled=False", flush=True)

print(f"DONE users_touched_settings={n}", flush=True)
