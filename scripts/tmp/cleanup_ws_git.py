import json, os

KEYS = ("git.enabled", "git.autoRepositoryDetection", "git.detectSubmodules", "git.repositoryScanMaxDepth")

paths = [
    "/home/farzadb/mounts/backend/.vscode/settings.json",
    "/home/farzadb/mounts/frontend/.vscode/settings.json",
    "/home/hosseinm/mounts/sepidz-web/.vscode/settings.json",
    "/home/hosseinm/mounts/sepidz-web/Backend/.vscode/settings.json",
    "/home/hosseinm/mounts/sepidz-web/Frontend/.vscode/settings.json",
    "/home/hosseinm/mounts/frontend/.vscode/settings.json",
    "/home/hosseinm/mounts/sepidzmenuonline/.vscode/settings.json",
    "/home/hosseinb/mounts/frontend/.vscode/settings.json",
    "/home/hosseinb/mounts/backend/.vscode/settings.json",
    "/home/hosseinb/mounts/portal/.vscode/settings.json",
    "/home/hosseinb/mounts/sima/.vscode/settings.json",
    "/home/nimaz/mounts/frontend/.vscode/settings.json",
    "/home/nimaz/mounts/nova/.vscode/settings.json",
    "/home/nimaz/mounts/sepidzwebapp/.vscode/settings.json",
]

for p in paths:
    if not os.path.isfile(p):
        continue
    try:
        data = json.load(open(p, encoding="utf-8"))
    except Exception as e:
        print(f"skip {p}: {e}", flush=True)
        continue
    if not isinstance(data, dict):
        continue
    changed = False
    for k in KEYS:
        if k in data:
            del data[k]
            changed = True
    if not changed:
        print(f"clean {p}", flush=True)
        continue
    if not data:
        os.remove(p)
        # remove empty .vscode if empty
        d = os.path.dirname(p)
        try:
            if not os.listdir(d):
                os.rmdir(d)
        except OSError:
            pass
        print(f"removed empty {p}", flush=True)
    else:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print(f"stripped {p}", flush=True)

# ensure user settings still disabled
for u in ("farzadb", "hosseinm", "hosseinb", "nimaz"):
    p = f"/home/{u}/.cursor-server/data/User/settings.json"
    if os.path.isfile(p):
        j = json.load(open(p))
        print(f"USER {u} git.enabled={j.get('git.enabled')}", flush=True)
print("DONE", flush=True)
