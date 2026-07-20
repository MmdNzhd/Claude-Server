import os
for base in [
    "/home/farzadb/.cursor-server/data",
    "/home/farzadb/.vscode-server/data",
]:
    print("===", base, flush=True)
    if not os.path.isdir(base):
        print("missing", flush=True)
        continue
    print("top", os.listdir(base), flush=True)
    user = os.path.join(base, "User")
    if os.path.isdir(user):
        print("User", os.listdir(user), flush=True)
        sp = os.path.join(user, "settings.json")
        print("settings exists", os.path.isfile(sp), flush=True)
        if os.path.isfile(sp):
            print(open(sp).read()[:500], flush=True)
    # Machine settings?
    for root, dirs, files in os.walk(base):
        if root.count(os.sep) - base.count(os.sep) > 3:
            dirs[:] = []
            continue
        for f in files:
            if f == "settings.json":
                print("FOUND", os.path.join(root, f), flush=True)
print("DONE", flush=True)
