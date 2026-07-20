import json, os, subprocess, sqlite3

u="farzadb"
home=f"/home/{u}"

print("=== Cursor User git settings ===", flush=True)
p=f"{home}/.cursor-server/data/User/settings.json"
if os.path.isfile(p):
    j=json.load(open(p))
    for k in ("git.enabled","git.autoRepositoryDetection","git.detectSubmodules","git.repositoryScanMaxDepth"):
        print(f"  {k}={j.get(k)!r}", flush=True)
else:
    print("  missing settings.json", flush=True)

print("\n=== git fsck-ish via laptop-exec as farzadb ===", flush=True)
for proj in ("frontend","backend"):
    cmd = f"su - {u} -c 'laptop-exec git -p {proj} -- status -sb && laptop-exec git -p {proj} -- rev-parse --is-inside-work-tree && laptop-exec git -p {proj} -- log -1 --oneline'"
    r = subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=90)
    out=((r.stdout or "")+(r.stderr or "")).strip()
    print(f"--- {proj} exit={r.returncode} ---", flush=True)
    print(out[:800] if out else "(empty)", flush=True)

print("\n=== .git object counts ===", flush=True)
for proj in ("frontend","backend"):
    obj=f"{home}/mounts/{proj}/.git/objects"
    if not os.path.isdir(obj):
        print(proj, "no objects dir", flush=True); continue
    n=0
    for root,dirs,files in os.walk(obj):
        n+=len(files)
        if n>5000: break
    print(f"{proj} object_files~={n} HEAD={open(f'{home}/mounts/{proj}/.git/HEAD').read().strip()}", flush=True)

print("DONE", flush=True)
