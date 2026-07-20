#!/usr/bin/env python3
"""Live edge-case matrix on Sepidz."""
import json, os, pwd, sqlite3, subprocess, sys

fails, warns, oks, edges = [], [], [], []
def OK(m): oks.append(m); print(f"OK  {m}", flush=True)
def FAIL(m): fails.append(m); print(f"FAIL {m}", flush=True)
def WARN(m): warns.append(m); print(f"WARN {m}", flush=True)
def EDGE(m): edges.append(m); print(f"EDGE {m}", flush=True)
def sh(cmd, t=30):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=t)

print("=" * 60, flush=True)
print("EDGE CASE AUDIT", flush=True)
print("=" * 60, flush=True)

# --- E1: policy files present & correct ---
cm = open("/usr/local/lib/claude-mount").read()
su = open("/usr/local/bin/laptop-exec-setup").read()
dle = ""
for p in ("/usr/local/lib/claude-server/commands/deploy-laptop-exec.sh",):
    if os.path.isfile(p):
        dle = open(p).read()

checks = [
    ("E1 mount applies SCM on warm", "_apply_git_scm_policy" in cm and "_warm_sshfs_cache" in cm),
    ("E1 setup reinforces git-off on login", "_ensure_cursor_git_off" in su),
    ("E1 deploy all uid>=1000", "getent passwd" in dle and "uid" not in dle.lower() or "1000" in dle),
    ("E1 deploy CRLF strip", "sed -i" in dle and r"\r" in dle),
    ("E1 no git shim", "git-via-laptop-exec" not in cm and not os.path.isfile("/usr/local/bin/git-via-laptop-exec")),
    ("E1 LE system CR=0", open("/usr/local/bin/laptop-exec","rb").read().count(b"\r")==0),
]
# fix deploy check properly
checks[2] = ("E1 deploy all uid>=1000", "getent passwd" in dle and "$3 >= 1000" in dle)

for name, ok in checks:
    (OK if ok else FAIL)(name)

ver = open("/usr/local/share/claude-client/connect-version.txt").read().strip()
OK(f"E1 sepidz_ver={ver}")

sud = open("/etc/sudoers.d/claude-client-deploy").read() if os.path.isfile("/etc/sudoers.d/claude-client-deploy") else ""
(OK if "NOPASSWD" in sud and "sepidz" in sud else FAIL)("E1 sudoers NOPASSWD sepidz")

# --- E2: per-user edge states ---
print("\n--- per-user edges ---", flush=True)
GOLD = open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")

for ent in sorted(pwd.getpwall(), key=lambda e: e.pw_name):
    if ent.pw_uid < 1000 or ent.pw_name in ("nobody","nfsnobody"):
        continue
    home = ent.pw_dir
    if not os.path.isdir(home):
        continue
    u = ent.pw_name
    confp = f"{home}/.claude-connect.conf"
    conf = {}
    if os.path.isfile(confp):
        for line in open(confp, errors="ignore"):
            if "=" in line and not line.startswith("#"):
                k,v = line.strip().split("=",1); conf[k.upper()]=v
    else:
        # no connect conf — edge: never connected
        if os.path.isdir(f"{home}/.cursor-server"):
            EDGE(f"{u}: has cursor-server but no .claude-connect.conf")
        continue

    gm = conf.get("GIT_MODE","?")
    port = conf.get("TUNNEL_PORT","")
    am = conf.get("ACTIVE_MOUNT","")
    os_ = conf.get("LAPTOP_OS","?")
    up = bool(port) and sh(f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'").returncode==0

    # E2a: GIT_MODE weird
    if gm not in ("off","hide","server"):
        WARN(f"{u}: unusual GIT_MODE={gm!r}")
    # E2b: tunnel down but mounts present
    mroot = f"{home}/mounts"
    mounts = []
    if os.path.isdir(mroot):
        try: mounts = sorted(os.listdir(mroot))
        except Exception: pass
    mounted = []
    for mid in mounts:
        mp = f"{mroot}/{mid}"
        # check /proc/mounts
        try:
            if any(mp in ln for ln in open("/proc/mounts")):
                mounted.append(mid)
        except Exception:
            pass
    if mounted and not up:
        EDGE(f"{u}: mounts still mounted {mounted} but tunnel DOWN :{port}")
    if up and am and am not in mounts and am not in mounted:
        EDGE(f"{u}: ACTIVE_MOUNT={am} not in mounts dirs={mounts}")

    # E2c: Cursor git must be off unless server mode
    sp = f"{home}/.cursor-server/data/User/settings.json"
    if os.path.isfile(sp):
        j = json.load(open(sp))
        if gm in ("server","on","yes","1","slow"):
            EDGE(f"{u}: GIT_MODE=server — git may be enabled intentionally enabled={j.get('git.enabled')}")
        else:
            if j.get("git.enabled") is not False:
                FAIL(f"{u}: Cursor git.enabled={j.get('git.enabled')} expected False")
            elif "git.path" in j:
                FAIL(f"{u}: git.path still set {j.get('git.path')}")
            else:
                OK(f"{u}: Cursor git OFF (mode={gm})")
    elif up:
        WARN(f"{u}: tunnel UP but no cursor User settings")

    # E2d: LE missing or CRLF
    le = f"{home}/.local/bin/laptop-exec"
    if os.path.isfile(le):
        cr = open(le,"rb").read().count(b"\r")
        if cr: FAIL(f"{u}: LE CRLF={cr}")
        else: OK(f"{u}: LE CR=0")
    else:
        if up: WARN(f"{u}: no ~/.local/bin/laptop-exec while online")
        else: EDGE(f"{u}: no LE (offline/never setup)")

    # E2e: machineid mismatch
    for label,p in [("profile",f"{home}/.config/Cursor/machineid"),("server",f"{home}/.cursor-server/data/machineid")]:
        if not os.path.isfile(p):
            if up: WARN(f"{u}: {label} mid missing")
            continue
        raw=open(p,"rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
        if raw != GOLD:
            FAIL(f"{u}: {label} mid != golden")
        else:
            OK(f"{u}: {label} mid OK")

    # E2f: tokens empty
    db=f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
    if os.path.isfile(db):
        c=sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        def gv(k):
            r=c.execute("select value from ItemTable where key=?",(k,)).fetchone()
            return "" if not r or r[0] is None else str(r[0])
        at,rt=gv("cursorAuth/accessToken"),gv("cursorAuth/refreshToken")
        c.close()
        if len(at)<20 or len(rt)<20:
            (FAIL if up else WARN)(f"{u}: weak tokens at={len(at)} rt={len(rt)}")
        else:
            OK(f"{u}: tokens OK")
    elif up:
        WARN(f"{u}: no state.vscdb")

    # E2g: .git.server-session residue with GIT_MODE=off (should be restored)
    if gm == "off" and mounted:
        for mid in mounted:
            mp = f"{mroot}/{mid}"
            # shallow check only
            ss = os.path.join(mp, ".git.server-session")
            g = os.path.join(mp, ".git")
            if os.path.exists(ss) and not os.path.exists(g):
                EDGE(f"{u}/{mid}: hide residue .git.server-session while GIT_MODE=off")
            # nested
            try:
                for name in os.listdir(mp):
                    if name.startswith("."): continue
                    p = os.path.join(mp, name)
                    if not os.path.isdir(p): continue
                    if os.path.exists(os.path.join(p,".git.server-session")) and not os.path.exists(os.path.join(p,".git")):
                        EDGE(f"{u}/{mid}/{name}: hide residue while off")
            except Exception:
                pass

    # E2h: workspace git.* pollution
    if mounted:
        for mid in mounted[:6]:
            vs = f"{mroot}/{mid}/.vscode/settings.json"
            if os.path.isfile(vs):
                try:
                    sj = json.load(open(vs, encoding="utf-8"))
                    gk = {k:sj[k] for k in sj if k.startswith("git.")}
                    if gk:
                        EDGE(f"{u}/{mid}: workspace git.* pollution {gk}")
                except Exception:
                    pass

    # E2i: automount stamp stale?
    stamp = f"{home}/.cache/claude-automount.stamp"
    if os.path.isfile(stamp):
        age = int(os.path.getmtime(stamp))
        import time
        EDGE(f"{u}: automount stamp age_s={int(time.time())-age}")

print("\n--- structural edges ---", flush=True)

# E3: hide mode trusted early return skips warm (document)
if "CLAUDE_TRUSTED_TUNNEL" in cm:
    EDGE("code: trusted-tunnel+hide can skip _warm_sshfs_cache on already-mounted")
# E4: vscode IDE shell skips automount
EDGE("code: Cursor/VSCODE_IPC_HOOK_CLI skips automount (by design)")
# E5: Smart frozen vs repo
EDGE("ops: Smart clients stay on .22 until tonight publish; Sepidz already .33")

# E6: root-owned files in user homes
for u in ("farzadb","hosseinm","hosseinb"):
    home=f"/home/{u}"
    for rel in (".cursor-server/data/User/settings.json",".local/bin/laptop-exec"):
        p=os.path.join(home,rel)
        if not os.path.exists(p): continue
        st=os.stat(p)
        owner=pwd.getpwuid(st.st_uid).pw_name
        if owner != u and owner != "root":
            WARN(f"{u}: {rel} owned by {owner}")
        elif owner == "root":
            FAIL(f"{u}: {rel} owned by root (user can't update)")
        else:
            OK(f"{u}: {rel} owner OK")

print("\n======== SUMMARY ========", flush=True)
print(f"ok={len(oks)} warn={len(warns)} fail={len(fails)} edge_notes={len(edges)}", flush=True)
for f in fails: print(f"  FAIL: {f}", flush=True)
for w in warns: print(f"  WARN: {w}", flush=True)
print("EDGE_GREEN" if not fails else "EDGE_RED", flush=True)
sys.exit(1 if fails else 0)
