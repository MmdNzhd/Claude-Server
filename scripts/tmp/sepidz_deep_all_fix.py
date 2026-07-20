#!/usr/bin/env python3
"""Deep Sepidz post-v33 audit + auto-fix for all users. Exit 1 if critical remains."""
import json, os, pwd, sqlite3, subprocess, sys, time

fails, warns, oks, fixes = [], [], [], []

def ok(m): oks.append(m); print(f"OK   {m}", flush=True)
def warn(m): warns.append(m); print(f"WARN {m}", flush=True)
def fail(m): fails.append(m); print(f"FAIL {m}", flush=True)
def fixed(m): fixes.append(m); print(f"FIX  {m}", flush=True)

def sh(cmd, timeout=40):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=timeout)

def strip_crlf(path):
    if not os.path.isfile(path):
        return False
    raw = open(path, "rb").read()
    if b"\r" not in raw:
        return False
    open(path, "wb").write(raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))
    return True

def chown_user(path, user):
    try:
        pw = pwd.getpwnam(user)
        os.chown(path, pw.pw_uid, pw.pw_gid)
    except Exception:
        pass

GOLD = open("/etc/cursor-auth/golden/machine-id.txt", "rb").read().replace(b"\r", b"").replace(b"\n", b"").strip().strip(b"\"'")
AUTH = json.load(open("/etc/cursor-auth/golden/auth.json"))
try:
    SK = json.load(open("/etc/cursor-auth/golden/state-keys.json"))
except Exception:
    SK = {}

print("=" * 64)
print("A) SYSTEM / BUNDLE v33")
print("=" * 64)

ver = open("/usr/local/share/claude-client/connect-version.txt").read().strip().replace("\r", "")
if ver != "20260717.33":
    fail(f"bundle version {ver} != 20260717.33")
else:
    ok(f"bundle {ver}")

req = [
    "connect.bat", "connect.ps1", "connect-update.ps1", "connect-ui.ps1",
    "connect-diagnostic.ps1", "git-mode.ps1", "editor-launch.ps1",
    "cursor-auth-laptop.ps1", "mac/connect.sh", "server/laptop-exec.sh",
    "server/claude-mount.sh", "manifest.txt",
]
for rel in req:
    p = f"/usr/local/share/claude-client/{rel}"
    if os.path.isfile(p):
        ok(f"has {rel}")
    else:
        fail(f"missing {rel}")

for p in ["/usr/local/bin/laptop-exec", "/usr/local/lib/claude-mount"]:
    rp = os.path.realpath(p)
    if strip_crlf(rp):
        fixed(f"CRLF stripped {rp}")
    cr = open(rp, "rb").read().count(b"\r")
    ok(f"{p} CR={cr}") if cr == 0 else fail(f"{p} still CRLF")

r = sh("sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh /tmp/nope.zip 2>&1")
out = (r.stdout or "") + (r.stderr or "")
if "password" in out.lower() and "not found" not in out.lower() and "FAIL" not in out:
    fail("sudo -n install wants password")
else:
    ok("sudo -n install-client-bundle OK")

if not AUTH.get("accessToken") or not AUTH.get("refreshToken"):
    fail("golden tokens empty")
else:
    ok(f"golden tokens ok len={len(str(AUTH['accessToken']))}")
if not AUTH.get("cachedEmail"):
    warn("golden cachedEmail empty (server-wide)")

print()
print("=" * 64)
print("B) ALL USERS — audit + fix")
print("=" * 64)

def ensure_mid(user, home):
    paths = [
        f"{home}/.config/Cursor/machineid",
        f"{home}/.cursor-server/data/machineid",
    ]
    os.makedirs(f"{home}/.config/Cursor", exist_ok=True)
    os.makedirs(f"{home}/.cursor-server/data", exist_ok=True)
    changed = False
    for p in paths:
        cur = b""
        if os.path.isfile(p):
            cur = open(p, "rb").read().replace(b"\r", b"").replace(b"\n", b"").strip().strip(b"\"'")
        if cur != GOLD:
            open(p, "wb").write(GOLD)
            chown_user(p, user)
            os.chmod(p, 0o644)
            changed = True
    return changed

def ensure_auth(user, home, db):
    os.makedirs(os.path.dirname(db), exist_ok=True)
    c = sqlite3.connect(db)
    cur = c.cursor()
    cur.execute("create table if not exists ItemTable (key text unique, value blob)")
    mapping = {
        "accessToken": "cursorAuth/accessToken",
        "refreshToken": "cursorAuth/refreshToken",
        "cachedEmail": "cursorAuth/cachedEmail",
        "cachedSignUpType": "cursorAuth/cachedSignUpType",
        "stripeMembershipType": "cursorAuth/stripeMembershipType",
        "stripeSubscriptionStatus": "cursorAuth/stripeSubscriptionStatus",
    }
    wrote = 0
    for src, dst in mapping.items():
        val = AUTH.get(src)
        if (val is None or str(val).strip() == "") and dst in SK:
            val = SK.get(dst)
        if val is None or str(val).strip() == "":
            continue
        cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (dst, str(val)))
        wrote += 1
    for k, v in SK.items():
        if v is None or (isinstance(v, str) and not v.strip()):
            continue
        if isinstance(v, (dict, list)):
            cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (k, json.dumps(v)))
        else:
            cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (k, str(v)))
        wrote += 1
    c.commit()
    # verify tokens
    def gv(k):
        r = cur.execute("select value from ItemTable where key=?", (k,)).fetchone()
        return "" if not r or r[0] is None else str(r[0])
    at, rt = gv("cursorAuth/accessToken"), gv("cursorAuth/refreshToken")
    c.close()
    chown_user(db, user)
    return len(at) > 20 and len(rt) > 20, wrote, len(at), len(rt)

def ensure_le(user, home):
    src = "/usr/local/bin/laptop-exec"
    dst = f"{home}/.local/bin/laptop-exec"
    os.makedirs(f"{home}/.local/bin", exist_ok=True)
    raw_src = open(src, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    need = True
    if os.path.isfile(dst):
        if open(dst, "rb").read() == raw_src:
            need = False
    if need:
        open(dst, "wb").write(raw_src)
        chown_user(dst, user)
        os.chmod(dst, 0o755)
        return True
    if strip_crlf(dst):
        chown_user(dst, user)
        return True
    return False

def disable_git_scm(user, mount_path):
    if not os.path.isdir(mount_path):
        return False
    # only if .git visible and GIT_MODE off later
    vs = os.path.join(mount_path, ".vscode")
    try:
        os.makedirs(vs, exist_ok=True)
        path = os.path.join(vs, "settings.json")
        data = {}
        if os.path.isfile(path):
            try:
                data = json.load(open(path))
                if not isinstance(data, dict):
                    data = {}
            except Exception:
                data = {}
        changed = data.get("git.enabled") is not False or data.get("git.autoRepositoryDetection") is not False
        data["git.enabled"] = False
        data["git.autoRepositoryDetection"] = False
        if changed or not os.path.isfile(path):
            open(path, "w").write(json.dumps(data, indent=2) + "\n")
            return True
    except Exception as e:
        warn(f"{user}: cannot write git settings under {mount_path}: {e}")
    return False

users = []
for line in open("/etc/passwd"):
    parts = line.split(":")
    if len(parts) < 6:
        continue
    u, uid, home = parts[0], int(parts[2]), parts[5]
    if uid < 1000 or u == "nobody":
        continue
    if not home.startswith("/home/") or not os.path.isdir(home):
        continue
    users.append((u, home))

print(f"{'USER':12} {'MID':3} {'TOK':3} {'LE':3} {'TUN':6} {'MOUNTS':28} NOTES")
for u, home in users:
    notes = []
    db = f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
    has_cursor = os.path.isfile(db) or os.path.isdir(f"{home}/.config/Cursor") or os.path.isdir(f"{home}/.cursor-server")

    # laptop-exec
    le_fixed = ensure_le(u, home)
    if le_fixed:
        fixed(f"{u}: laptop-exec refreshed")
        notes.append("le-fix")
    le_path = f"{home}/.local/bin/laptop-exec"
    le_ok = os.path.isfile(le_path) and open(le_path, "rb").read().count(b"\r") == 0

    # machineid + auth if cursor-ish
    mid_ok = True
    tok_ok = True
    if has_cursor or os.path.isfile(db):
        if ensure_mid(u, home):
            fixed(f"{u}: machineid aligned")
            notes.append("mid-fix")
        # verify
        for p in [f"{home}/.config/Cursor/machineid", f"{home}/.cursor-server/data/machineid"]:
            if not os.path.isfile(p):
                mid_ok = False
            else:
                cur = open(p, "rb").read().replace(b"\r", b"").replace(b"\n", b"").strip().strip(b"\"'")
                if cur != GOLD:
                    mid_ok = False
        if os.path.isfile(db) or has_cursor:
            if not os.path.isfile(db):
                # create empty db path and fill
                os.makedirs(os.path.dirname(db), exist_ok=True)
            tok_ok, wrote, alen, rlen = ensure_auth(u, home, db)
            if wrote:
                notes.append(f"auth-merge:{wrote}")
            if not tok_ok:
                # try claude-server sync
                sh(f"claude-server sync-cursor-auth {u}")
                tok_ok, wrote, alen, rlen = ensure_auth(u, home, db)
            if not tok_ok:
                fail(f"{u}: tokens still bad")
                notes.append("TOK-FAIL")
    else:
        mid_ok = True  # N/A
        tok_ok = True

    # tunnel
    conf_p = f"{home}/.claude-connect.conf"
    tun = "-"
    git_mode = "?"
    if os.path.isfile(conf_p):
        kv = {}
        for ln in open(conf_p):
            if "=" in ln:
                k, v = ln.strip().split("=", 1)
                kv[k] = v
        git_mode = kv.get("GIT_MODE", "?")
        port = kv.get("TUNNEL_PORT", "")
        if port:
            r = sh(f"timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}' && echo open || echo closed")
            tun = "UP" if "open" in r.stdout else "DOWN"
        else:
            tun = "noport"
    else:
        tun = "noconf"

    # mounts
    mounted = []
    mdir = f"{home}/mounts"
    if os.path.isdir(mdir):
        for name in sorted(os.listdir(mdir)):
            mp = os.path.join(mdir, name)
            if not os.path.isdir(mp):
                continue
            r = sh(f"mountpoint -q '{mp}' && echo yes || echo no")
            if "yes" in r.stdout:
                mounted.append(name)
                # readability
                r2 = sh(f"timeout 6 ls '{mp}' | head -2")
                if r2.returncode != 0 or not r2.stdout.strip():
                    fail(f"{u}: mount {name} unreadable")
                    notes.append(f"{name}:unreadable")
                # git scm disable if .git visible
                if os.path.exists(os.path.join(mp, ".git")) and git_mode in ("off", "hide", "?"):
                    if disable_git_scm(u, mp):
                        fixed(f"{u}:{name} git.enabled=false")
                        notes.append(f"{name}:git-off")
                # also child Backend/Frontend
                for child in ("Backend", "Frontend", "backend", "frontend"):
                    cp = os.path.join(mp, child)
                    if os.path.isdir(cp) and os.path.exists(os.path.join(cp, ".git")):
                        if disable_git_scm(u, cp):
                            fixed(f"{u}:{name}/{child} git.enabled=false")

    status = "PASS"
    if not le_ok:
        status = "FAIL"; fail(f"{u}: laptop-exec CRLF/missing")
    if has_cursor and not mid_ok:
        status = "FAIL"; fail(f"{u}: machineid bad")
    if has_cursor and os.path.isfile(db) and not tok_ok:
        status = "FAIL"

    print(f"{u:12} {'Y' if mid_ok else 'N':3} {'Y' if tok_ok else 'N':3} {'Y' if le_ok else 'N':3} {tun:6} {','.join(mounted) or '-':28} {status} {' '.join(notes)}", flush=True)
    if status == "PASS":
        ok(f"user {u} PASS")

print()
print("=" * 64)
print("C) LIVE USERS DEEP (tunnel UP)")
print("=" * 64)

live = []
for u, home in users:
    conf_p = f"{home}/.claude-connect.conf"
    if not os.path.isfile(conf_p):
        continue
    kv = {}
    for ln in open(conf_p):
        if "=" in ln:
            k, v = ln.strip().split("=", 1)
            kv[k] = v
    port = kv.get("TUNNEL_PORT", "")
    if not port:
        continue
    r = sh(f"timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}' && echo open || echo closed")
    if "open" in r.stdout:
        live.append((u, home, kv))

for u, home, kv in live:
    print(f"--- {u} port={kv.get('TUNNEL_PORT')} git={kv.get('GIT_MODE')} mount={kv.get('ACTIVE_MOUNT')} ---")
    # shell
    t0 = time.time()
    r = sh(f"timeout 5 su - {u} -c 'echo SHELL_OK'")
    dt = time.time() - t0
    if "SHELL_OK" in r.stdout:
        ok(f"{u}: shell {dt:.2f}s")
    else:
        fail(f"{u}: shell fail {r.stderr[:120]}")
    # laptop-exec
    r = sh(f"su - {u} -c 'laptop-exec status'")
    out = r.stdout + r.stderr
    if "UP" in out and "tunnel:" in out:
        ok(f"{u}: laptop-exec UP")
    else:
        fail(f"{u}: laptop-exec status bad: {out[:180]}")
    # IO on each mounted project
    mdir = f"{home}/mounts"
    if os.path.isdir(mdir):
        for name in sorted(os.listdir(mdir)):
            mp = os.path.join(mdir, name)
            r = sh(f"mountpoint -q '{mp}' && echo yes || echo no")
            if "yes" not in r.stdout:
                continue
            # laptop-exec write probe
            r = sh(
                f"su - {u} -c 'printf deep33 > /tmp/d33.txt && "
                f"laptop-exec write -p {name} .deep33-e2e.txt < /tmp/d33.txt && "
                f"laptop-exec read -p {name} .deep33-e2e.txt && "
                f"laptop-exec run -p {name} -- cmd /c del .deep33-e2e.txt'"
            )
            if "deep33" in r.stdout:
                ok(f"{u}: {name} laptop-exec IO")
            else:
                # try without del
                r2 = sh(
                    f"su - {u} -c 'printf deep33 > /tmp/d33.txt && "
                    f"laptop-exec write -p {name} .deep33-e2e.txt < /tmp/d33.txt && "
                    f"laptop-exec read -p {name} .deep33-e2e.txt'"
                )
                if "deep33" in r2.stdout:
                    ok(f"{u}: {name} laptop-exec IO (no del)")
                    sh(f"su - {u} -c 'laptop-exec run -p {name} -- cmd /c del .deep33-e2e.txt' >/dev/null 2>&1 || true")
                else:
                    fail(f"{u}: {name} IO fail: {(r.stderr or r.stdout or r2.stderr)[:200]}")

# remount farzadb if needed
print()
print("=" * 64)
print("D) FARZADB FORCE HEALTH")
print("=" * 64)
u = "farzadb"
home = "/home/farzadb"
if os.path.isdir(home):
    ensure_mid(u, home)
    ensure_auth(u, home, f"{home}/.config/Cursor/User/globalStorage/state.vscdb")
    ensure_le(u, home)
    sh("claude-server sync-cursor-auth farzadb")
    # remount
    r = sh("su - farzadb -c 'CLAUDE_TRUSTED_TUNNEL=1 claude-mount up frontend; CLAUDE_TRUSTED_TUNNEL=1 claude-mount up backend; claude-mount status'")
    print(r.stdout)
    if r.stderr:
        print(r.stderr)
    for mid in ("frontend", "backend"):
        mp = f"{home}/mounts/{mid}"
        r = sh(f"mountpoint -q {mp} && timeout 5 ls {mp} | head -3")
        ok(f"farzadb {mid} mounted+ls") if r.returncode == 0 and r.stdout.strip() else fail(f"farzadb {mid} mount/ls fail")
    # hosseinm
    if os.path.isdir("/home/hosseinm"):
        ensure_mid("hosseinm", "/home/hosseinm")
        ensure_auth("hosseinm", "/home/hosseinm", "/home/hosseinm/.config/Cursor/User/globalStorage/state.vscdb")
        ensure_le("hosseinm", "/home/hosseinm")
        sh("claude-server sync-cursor-auth hosseinm")
        r = sh("su - hosseinm -c 'CLAUDE_TRUSTED_TUNNEL=1 claude-mount up sepidz-web; claude-mount status'")
        print("hosseinm:", r.stdout.strip())
        ok("hosseinm remount attempted")

print()
print("=" * 64)
print(f"SUMMARY ok={len(oks)} warn={len(warns)} fix={len(fixes)} fail={len(fails)}")
for x in fixes:
    print(" FIX:", x)
for x in warns:
    print(" WARN:", x)
for x in fails:
    print(" FAIL:", x)
open("/tmp/sepidz-deep-all-report.txt", "w").write(
    f"ok={len(oks)} warn={len(warns)} fix={len(fixes)} fail={len(fails)}\n"
    + "\n".join("OK " + x for x in oks) + "\n"
    + "\n".join("FIX " + x for x in fixes) + "\n"
    + "\n".join("WARN " + x for x in warns) + "\n"
    + "\n".join("FAIL " + x for x in fails) + "\n"
)
sys.exit(1 if fails else 0)
