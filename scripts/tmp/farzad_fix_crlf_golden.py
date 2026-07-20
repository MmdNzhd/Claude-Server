import os, subprocess, sqlite3, json

def sh(cmd):
    print("+", cmd, flush=True)
    r = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    if r.stdout: print(r.stdout.rstrip(), flush=True)
    if r.stderr: print(r.stderr.rstrip(), flush=True)
    return r

def strip_crlf(path):
    if not os.path.isfile(path):
        print("missing", path); return False
    raw = open(path, "rb").read()
    if b"\r" not in raw:
        print("clean", path); return False
    open(path, "wb").write(raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))
    print("stripped_crlf", path, "bytes", len(raw))
    return True

print("=== strip server laptop-exec binaries ===")
for p in [
    "/usr/local/bin/laptop-exec",
    "/usr/local/lib/claude-mount",
    "/usr/local/bin/claude-mount",
    "/usr/local/share/claude-client/server/laptop-exec.sh",
    "/usr/local/share/claude-client/server/claude-mount.sh",
]:
    # follow symlink
    real = os.path.realpath(p) if os.path.exists(p) else p
    strip_crlf(real)

print("=== strip all users ~/.local/bin/laptop-exec ===")
for home in sorted(os.listdir("/home")):
    p = f"/home/{home}/.local/bin/laptop-exec"
    if os.path.isfile(p) or os.path.islink(p):
        real = os.path.realpath(p)
        changed = strip_crlf(real)
        # also fix the path itself if not symlink to system
        if os.path.isfile(p) and not os.path.islink(p):
            strip_crlf(p)
        st = os.stat(real)
        # keep ownership if under home
        if real.startswith(f"/home/{home}/"):
            import pwd, grp
            try:
                pw = pwd.getpwnam(home)
                os.chown(real, pw.pw_uid, pw.pw_gid)
            except Exception:
                pass

print("=== farzadb laptop-exec smoke ===")
r = sh("su - farzadb -c 'file $(readlink -f ~/.local/bin/laptop-exec 2>/dev/null || echo ~/.local/bin/laptop-exec); laptop-exec status; laptop-exec health | head -20'")

print("=== try fill identity from hosseinm if better ===")
for u in ["hosseinm", "farzadb", "smart", "sepidz"]:
    db = f"/home/{u}/.config/Cursor/User/globalStorage/state.vscdb"
    if not os.path.isfile(db):
        continue
    try:
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = list(c.execute("select key,value from ItemTable where key like 'cursorAuth/%'"))
        print(f"user={u}")
        for k,v in rows:
            s = "" if v is None else str(v)
            print(f"  {k} len={len(s)} empty={not s.strip()} preview={s[:50]!r}")
        c.close()
    except Exception as e:
        print(u, e)

# If Smart-like user on this box? check /etc/cursor-auth for other files
print("=== golden dir ===")
sh("ls -la /etc/cursor-auth/golden/")
sh("python3 -c \"import json; a=json.load(open('/etc/cursor-auth/golden/auth.json')); print({k:(len(str(v)) if v is not None else None) for k,v in a.items()})\"")

# Frontend permission via laptop-exec simpler
print("=== frontend write via laptop-exec ===")
r = sh("su - farzadb -c 'printf probe2 > /tmp/p2.txt && laptop-exec write -p frontend .claude-e2e-probe2.txt < /tmp/p2.txt && laptop-exec read -p frontend .claude-e2e-probe2.txt && laptop-exec run -p frontend -- cmd /c del .claude-e2e-probe2.txt'")

# SSHFS frontend write as farzadb into a writable subdir?
print("=== frontend SSHFS write locations ===")
r = sh("su - farzadb -c 'touch /home/farzadb/mounts/frontend/.cursor/e2e-touch 2>&1; ls -ld /home/farzadb/mounts/frontend /home/farzadb/mounts/frontend/.cursor 2>&1'")

print("DONE")
