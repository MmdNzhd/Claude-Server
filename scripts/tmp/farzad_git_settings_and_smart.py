import json, os, subprocess

def sh(cmd):
    print("+", cmd, flush=True)
    r = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    if r.stdout: print(r.stdout.rstrip(), flush=True)
    if r.stderr: print(r.stderr.rstrip(), flush=True)
    return r

# Disable Cursor SCM git on farzadb mounts (GIT_MODE=off + .git visible)
for mid in ("frontend", "backend"):
    base = f"/home/farzadb/mounts/{mid}/.vscode"
    os.makedirs(base, exist_ok=True)
    path = f"{base}/settings.json"
    data = {}
    if os.path.isfile(path):
        try:
            data = json.load(open(path))
            if not isinstance(data, dict):
                data = {}
        except Exception:
            data = {}
    data["git.enabled"] = False
    data["git.autoRepositoryDetection"] = False
    open(path, "w").write(json.dumps(data, indent=2) + "\n")
    # chown farzadb
    os.system(f"chown -R farzadb:farzadb {base}")
    print("wrote", path, data)

# same for hosseinm sepidz-web if mounted
for mid in ("sepidz-web",):
    mp = f"/home/hosseinm/mounts/{mid}"
    if not os.path.isdir(mp):
        continue
    # also Backend/Frontend children
    targets = [mp, f"{mp}/Backend", f"{mp}/Frontend"]
    for t in targets:
        if not os.path.isdir(t):
            continue
        base = f"{t}/.vscode"
        os.makedirs(base, exist_ok=True)
        path = f"{base}/settings.json"
        data = {}
        if os.path.isfile(path):
            try:
                data = json.load(open(path))
                if not isinstance(data, dict):
                    data = {}
            except Exception:
                data = {}
        data["git.enabled"] = False
        data["git.autoRepositoryDetection"] = False
        open(path, "w").write(json.dumps(data, indent=2) + "\n")
        os.system(f"chown -R hosseinm:hosseinm {base}")
        print("wrote", path)

print("DONE_GIT_SETTINGS")
