import os, glob, json
u = "farzadb"
home = f"/home/{u}"
for base in [f"{home}/.cursor-server", f"{home}/.vscode-server", f"{home}/.cursor"]:
    print("BASE", base, "exists", os.path.isdir(base), flush=True)
    if not os.path.isdir(base):
        continue
    # shallow list
    try:
        print("  top:", sorted(os.listdir(base))[:30], flush=True)
    except Exception as e:
        print("  list_err", e, flush=True)
        continue
    for root, dirs, files in os.walk(base):
        depth = root[len(base):].count(os.sep)
        if depth > 5:
            dirs[:] = []
            continue
        if "settings.json" in files:
            p = os.path.join(root, "settings.json")
            print("SETTINGS", p, flush=True)
            try:
                print(" ", open(p).read()[:300], flush=True)
            except Exception as e:
                print("  read_err", e, flush=True)
        # prune heavy
        dirs[:] = [d for d in dirs if d not in ("node_modules", "logs", "CachedExtensionVSIXs", "CachedProfilesData")]
print("DONE", flush=True)
