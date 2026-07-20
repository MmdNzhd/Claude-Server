#!/usr/bin/env python3
"""Deep Sepidz audit: all users + system + farzadb focus. Exit 1 if critical fails."""
import json, os, sqlite3, subprocess, sys, hashlib, time

fails, warns, oks = [], [], []

def ok(m): oks.append(m); print(f"OK   {m}", flush=True)
def warn(m): warns.append(m); print(f"WARN {m}", flush=True)
def fail(m): fails.append(m); print(f"FAIL {m}", flush=True)

def sh(cmd, timeout=30):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=timeout)

def has_crlf(path):
    try:
        return b"\r" in open(path, "rb").read()
    except Exception:
        return False

def strip_crlf(path):
    raw = open(path, "rb").read()
    if b"\r" not in raw:
        return False
    open(path, "wb").write(raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))
    return True

print("=" * 60)
print("A) SYSTEM BINARIES + BUNDLE")
print("=" * 60)

# system binaries
for p in ["/usr/local/bin/laptop-exec", "/usr/local/lib/claude-mount", "/usr/local/bin/claude-mount"]:
    rp = os.path.realpath(p) if os.path.exists(p) else p
    if not os.path.isfile(rp):
        fail(f"missing {p}")
        continue
    if has_crlf(rp):
        strip_crlf(rp)
        warn(f"stripped CRLF {rp}")
    else:
        ok(f"LF {p} -> {rp}")

# bundle
ver = open("/usr/local/share/claude-client/connect-version.txt").read().strip().replace("\r","")
ok(f"bundle version {ver}")
required = [
    "connect.bat","connect.ps1","connect-update.ps1","connect-ui.ps1","connect-version.txt",
    "git-mode.ps1","editor-launch.ps1","cursor-auth-laptop.ps1","connect-diagnostic.ps1",
    "mac/connect.sh","mac/connect-update.sh","mac/git-mode.sh",
    "server/laptop-exec.sh","server/claude-mount.sh","manifest.txt",
]
for rel in required:
    p = f"/usr/local/share/claude-client/{rel}"
    if os.path.isfile(p):
        if rel.endswith(".sh") and has_crlf(p):
            strip_crlf(p); warn(f"stripped CRLF bundle {rel}")
        else:
            ok(f"bundle has {rel}")
    else:
        fail(f"bundle missing {rel}")

# sudoers nopasswd
r = sh("sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh /tmp/nope.zip 2>&1")
out = (r.stdout or "") + (r.stderr or "")
if "password" in out.lower() and "bundle not found" not in out.lower() and "not found" not in out.lower():
    fail(f"sudo -n install asks password: {out[:200]}")
elif "not found" in out.lower() or "FAIL" in out or "bundle" in out.lower():
    ok("sudo -n install-client-bundle works (nopasswd)")
else:
    warn(f"sudo -n unexpected: {out[:200]}")

installer = "/usr/local/lib/claude-server/commands/install-client-bundle.sh"
ok("installer present") if os.path.isfile(installer) else fail("installer missing")
ok("sudoers present") if os.path.isfile("/etc/sudoers.d/claude-client-deploy") else fail("sudoers missing")

gold = open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
auth = json.load(open("/etc/cursor-auth/golden/auth.json"))
ok(f"golden mid {gold.decode()}")
for k in ("accessToken","refreshToken"):
    if auth.get(k): ok(f"golden {k} len={len(str(auth[k]))}")
    else: fail(f"golden {k} empty")
for k in ("cachedEmail","stripeMembershipType"):
    if auth.get(k): ok(f"golden {k} set")
    else: warn(f"golden {k} empty (server-wide identity incomplete)")

print()
print("=" * 60)
print("B) ALL USERS")
print("=" * 60)

rows = []
for line in open("/etc/passwd"):
    parts = line.strip().split(":")
    if len(parts) < 6: continue
    u, uid, home, shell = parts[0], int(parts[2]), parts[5], parts[6] if len(parts)>6 else ""
    if uid < 1000 or u in ("nobody",): continue
    if not home.startswith("/home/") or not os.path.isdir(home): continue

    mid_p = f"{home}/.config/Cursor/machineid"
    mid_s = f"{home}/.cursor-server/data/machineid"
    db = f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
    le = f"{home}/.local/bin/laptop-exec"
    conf = f"{home}/.claude-connect.conf"

    # CRLF
    crlf = False
    if os.path.exists(le):
        rp = os.path.realpath(le)
        if has_crlf(rp) or (os.path.isfile(le) and not os.path.islink(le) and has_crlf(le)):
            crlf = True
            strip_crlf(rp)
            if os.path.isfile(le) and not os.path.islink(le):
                strip_crlf(le)
            try:
                import pwd
                pw = pwd.getpwnam(u)
                os.chown(rp, pw.pw_uid, pw.pw_gid)
            except Exception:
                pass

    # machineid
    mid_ok = False
    has_cursor = os.path.isfile(db)
    if has_cursor:
        def read_mid(p):
            if not os.path.isfile(p): return None
            return open(p,"rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
        mp, ms = read_mid(mid_p), read_mid(mid_s)
        if mp == gold and ms == gold:
            mid_ok = True
        else:
            # auto-fix
            os.makedirs(os.path.dirname(mid_p), exist_ok=True)
            os.makedirs(os.path.dirname(mid_s), exist_ok=True)
            open(mid_p,"wb").write(gold)
            open(mid_s,"wb").write(gold)
            import pwd
            pw = pwd.getpwnam(u)
            os.chown(mid_p, pw.pw_uid, pw.pw_gid)
            os.chown(mid_s, pw.pw_uid, pw.pw_gid)
            mid_ok = True
            warn(f"{u}: fixed machineid")

    # auth tokens
    tok_ok = False
    auth_detail = "no-db"
    if has_cursor:
        try:
            c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            def gv(k):
                r = c.execute("select value from ItemTable where key=?", (k,)).fetchone()
                return "" if not r or r[0] is None else str(r[0])
            at, rt = gv("cursorAuth/accessToken"), gv("cursorAuth/refreshToken")
            email = gv("cursorAuth/cachedEmail")
            c.close()
            tok_ok = len(at) > 20 and len(rt) > 20
            auth_detail = f"tok={'Y' if tok_ok else 'N'} email={'Y' if email.strip() else 'N'}"
            if not tok_ok:
                # merge tokens from golden
                c = sqlite3.connect(db)
                cur = c.cursor()
                cur.execute("create table if not exists ItemTable (key text unique, value blob)")
                for src,dst in [("accessToken","cursorAuth/accessToken"),("refreshToken","cursorAuth/refreshToken")]:
                    if auth.get(src):
                        cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (dst, str(auth[src])))
                c.commit(); c.close()
                import pwd
                pw = pwd.getpwnam(u)
                os.chown(db, pw.pw_uid, pw.pw_gid)
                tok_ok = True
                warn(f"{u}: restored tokens from golden")
                auth_detail = "tok=Y(restored) email=N"
        except Exception as e:
            auth_detail = f"db-err:{e}"
            fail(f"{u}: db error {e}")

    # tunnel
    tunnel = "-"
    port = ""
    if os.path.isfile(conf):
        kv = {}
        for ln in open(conf):
            if "=" in ln:
                k,v = ln.strip().split("=",1); kv[k]=v
        port = kv.get("TUNNEL_PORT","")
        if port:
            r = sh(f"timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}' && echo open || echo closed")
            tunnel = "UP" if "open" in r.stdout else "DOWN"
        else:
            tunnel = "no-port"
    else:
        tunnel = "no-conf"

    # mounts
    mounts_dir = f"{home}/mounts"
    mounted = []
    if os.path.isdir(mounts_dir):
        for name in sorted(os.listdir(mounts_dir)):
            mp = os.path.join(mounts_dir, name)
            if not os.path.isdir(mp): continue
            r = sh(f"mountpoint -q {mp} && echo yes || echo no")
            if "yes" in r.stdout:
                mounted.append(name)

    status = "PASS"
    notes = []
    if crlf: notes.append("crlf-fixed")
    if has_cursor and not mid_ok: status="FAIL"; notes.append("mid")
    if has_cursor and not tok_ok: status="FAIL"; notes.append("tok")
    if has_cursor and tunnel == "DOWN": notes.append("tunnel-down")
    row = f"{u:12} mid={'Y' if mid_ok or not has_cursor else 'N'} auth={auth_detail:24} crlf={'fixed' if crlf else 'LF':5} tunnel={tunnel:8} mounts={','.join(mounted) or '-':20} {status} {' '.join(notes)}"
    print(row, flush=True)
    rows.append((u, status, notes, has_cursor, tunnel, mounted))
    if status == "PASS":
        ok(f"user {u} PASS")
    else:
        fail(f"user {u} FAIL {notes}")

print()
print("=" * 60)
print("C) FARZADB DEEP")
print("=" * 60)
U="farzadb"; HOME=f"/home/{U}"

# shell
t0=time.time(); r=sh(f"timeout 5 su - {U} -c 'echo SHELL_OK'"); dt=time.time()-t0
ok(f"shell {dt:.2f}s") if "SHELL_OK" in r.stdout else fail("shell fail")

# laptop-exec
r=sh(f"su - {U} -c 'laptop-exec status'")
out=r.stdout+r.stderr
ok("laptop-exec UP") if "UP" in out else fail(f"laptop-exec: {out[:200]}")
r=sh(f"su - {U} -c 'laptop-exec health'")
ok("laptop-exec health") if "frontend" in r.stdout or "backend" in r.stdout else warn(f"health: {r.stdout[:150]}")

# IO probes both projects
for proj in ("frontend","backend"):
    r=sh(f"su - {U} -c 'printf deep > /tmp/d.txt && laptop-exec write -p {proj} .deep-e2e.txt < /tmp/d.txt && laptop-exec read -p {proj} .deep-e2e.txt && laptop-exec run -p {proj} -- cmd /c del .deep-e2e.txt'")
    if "deep" in r.stdout:
        ok(f"{proj} laptop-exec IO")
    else:
        fail(f"{proj} IO fail out={r.stdout!r} err={r.stderr!r}")

# mount read
for mid in ("frontend","backend"):
    mp=f"{HOME}/mounts/{mid}"
    r=sh(f"mountpoint -q {mp} && timeout 8 ls {mp} | head -3")
    ok(f"{mid} mount ls") if r.returncode==0 and r.stdout.strip() else fail(f"{mid} mount ls fail")

# bashrc hang suspects
r=sh(f"grep -nE 'sleep |while |sshfs|claude-mount|nc -|curl ' {HOME}/.bashrc {HOME}/.profile 2>/dev/null | head")
if r.stdout.strip():
    warn(f"bashrc suspects:\n{r.stdout.strip()}")
else:
    ok("bashrc no hang suspects")

# recent cursor errors
logdir=f"{HOME}/.cursor-server/data/logs"
if os.path.isdir(logdir):
    logs=sorted([os.path.join(logdir,d,"remoteagent.log") for d in os.listdir(logdir) if os.path.isfile(os.path.join(logdir,d,"remoteagent.log"))], key=os.path.getmtime, reverse=True)
    if logs:
        r=sh(f"grep -iE 'error|fail|unauthor|denied|auth' {logs[0]} | tail -15")
        if r.stdout.strip():
            # filter noise
            lines=[ln for ln in r.stdout.splitlines() if "typescript" not in ln.lower() and "extensions control" not in ln.lower()]
            if lines:
                warn(f"recent remoteagent issues ({len(lines)}):\n" + "\n".join(lines[-8:]))
            else:
                ok("remoteagent no critical auth errors (noise filtered)")
        else:
            ok("remoteagent no error lines")
else:
    warn("no cursor logs dir")

# git mode / .git visibility
conf={}
for ln in open(f"{HOME}/.claude-connect.conf"):
    if "=" in ln: k,v=ln.strip().split("=",1); conf[k]=v
ok(f"GIT_MODE={conf.get('GIT_MODE')}")
for mid in ("frontend","backend"):
    for g in (".git",".git.server-session"):
        p=f"{HOME}/mounts/{mid}/{g}"
        if os.path.exists(p):
            warn(f"{mid} has {g} visible (GIT_MODE={conf.get('GIT_MODE')} — SSHFS git risk)") if conf.get("GIT_MODE")=="off" and g==".git" else ok(f"{mid} {g} present")
    vs=f"{HOME}/mounts/{mid}/.vscode/settings.json"
    if os.path.isfile(vs):
        try:
            s=json.load(open(vs))
            if s.get("git.enabled") is False:
                ok(f"{mid} git.enabled=false")
            else:
                warn(f"{mid} .vscode/settings git.enabled={s.get('git.enabled')}")
        except Exception as e:
            warn(f"{mid} settings parse {e}")
    else:
        warn(f"{mid} no .vscode/settings.json (git SCM not disabled for off mode)")

print()
print("=" * 60)
print(f"SUMMARY ok={len(oks)} warn={len(warns)} fail={len(fails)}")
for w in warns: print(" WARN:", w)
for f in fails: print(" FAIL:", f)
# write report
open("/tmp/sepidz-deep-audit-report.txt","w").write(
    f"ok={len(oks)} warn={len(warns)} fail={len(fails)}\n" +
    "\n".join("OK "+x for x in oks)+"\n"+
    "\n".join("WARN "+x for x in warns)+"\n"+
    "\n".join("FAIL "+x for x in fails)+"\n"
)
sys.exit(1 if fails else 0)
