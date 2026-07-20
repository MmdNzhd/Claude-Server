import os, json, subprocess, pwd

u = "farzadb"
home = f"/home/{u}"
print("=== farzadb git DIAG ===", flush=True)

conf = os.path.join(home, ".claude-connect.conf")
if os.path.isfile(conf):
    print("CONF:", open(conf).read().strip(), flush=True)

# tunnel
port = None
for line in open(conf) if os.path.isfile(conf) else []:
    if line.upper().startswith("TUNNEL_PORT="):
        port = line.split("=",1)[1].strip()
print("tunnel_port", port, flush=True)
if port:
    r = subprocess.run(["bash","-c", f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'"], capture_output=True)
    print("tunnel_up", r.returncode==0, flush=True)

for mid in ("frontend", "backend"):
    mp = f"{home}/mounts/{mid}"
    print(f"\n--- mounts/{mid} exists={os.path.isdir(mp)} ---", flush=True)
    if not os.path.isdir(mp):
        continue
    # check mount
    try:
        with open("/proc/mounts") as f:
            mounted = any(mp in line for line in f)
        print("ismount_proc", mounted, flush=True)
    except Exception as e:
        print("mount_check_err", e, flush=True)

    for name in (".git", ".git.server-session", ".git.server-session.bak", ".gitignore"):
        p = os.path.join(mp, name)
        print(f"  {name}: exists={os.path.exists(p)} isdir={os.path.isdir(p)} isfile={os.path.isfile(p)}", flush=True)
        if os.path.exists(p):
            try:
                st = os.lstat(p)
                print(f"    mode={oct(st.st_mode)} size={st.st_size} symlink={os.path.islink(p)}", flush=True)
                if os.path.islink(p):
                    print(f"    link->{os.readlink(p)}", flush=True)
            except Exception as e:
                print(f"    stat_err={e}", flush=True)
            if os.path.isdir(p):
                try:
                    kids = os.listdir(p)[:30]
                    print(f"    entries({len(os.listdir(p))}): {kids}", flush=True)
                except Exception as e:
                    print(f"    list_err={e}", flush=True)
            if os.path.isfile(p) and name == ".git":
                try:
                    print(f"    content={open(p).read()[:200]!r}", flush=True)
                except Exception as e:
                    print(f"    read_err={e}", flush=True)

    # HEAD / config quick
    for rel in (".git/HEAD", ".git/config", ".git.server-session/HEAD", ".git.server-session/config"):
        p = os.path.join(mp, rel)
        if os.path.isfile(p):
            try:
                print(f"  {rel}: {open(p).read().strip()[:120]!r}", flush=True)
            except Exception as e:
                print(f"  {rel} err={e}", flush=True)

    # vscode settings
    vs = os.path.join(mp, ".vscode", "settings.json")
    if os.path.isfile(vs):
        try:
            print(f"  vscode_settings: {open(vs).read()[:300]}", flush=True)
        except Exception as e:
            print(f"  vscode_err={e}", flush=True)

# also check if git was renamed at laptop via listing .git*
print("\n=== top-level hidden git-ish in mounts ===", flush=True)
for mid in ("frontend", "backend"):
    mp = f"{home}/mounts/{mid}"
    if not os.path.isdir(mp):
        continue
    try:
        names = [n for n in os.listdir(mp) if "git" in n.lower()]
        print(mid, names, flush=True)
    except Exception as e:
        print(mid, "list_err", e, flush=True)

print("DONE", flush=True)
