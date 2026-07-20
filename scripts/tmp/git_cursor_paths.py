import os, glob
users = ["farzadb", "hosseinm", "hosseinb"]
cands = [
    ".cursor-server/data/User/settings.json",
    ".cursor-server/User/settings.json",
    ".config/Cursor/User/settings.json",
    ".config/Code/User/settings.json",
    ".local/share/cursor-agent/...",
]
for u in users:
    home = f"/home/{u}"
    print(f"=== {u}", flush=True)
    for pat in [
        f"{home}/.cursor-server/**/User/settings.json",
        f"{home}/.cursor*/**/settings.json",
        f"{home}/.config/**/User/settings.json",
    ]:
        for p in glob.glob(pat, recursive=True)[:20]:
            print(" ", p, flush=True)
    # also list top-level hidden
    try:
        for n in sorted(os.listdir(home)):
            if "cursor" in n.lower() or n in (".vscode-server", ".config"):
                print(" dir", n, flush=True)
                p = os.path.join(home, n)
                if os.path.isdir(p):
                    for root, dirs, files in os.walk(p):
                        if "settings.json" in files and "User" in root:
                            print("  FOUND", os.path.join(root, "settings.json"), flush=True)
                        # prune deep
                        if root.count(os.sep) - home.count(os.sep) > 6:
                            dirs[:] = []
    except Exception as e:
        print("err", e, flush=True)
print("DONE", flush=True)
