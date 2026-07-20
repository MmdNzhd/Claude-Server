#!/usr/bin/env python3
import json, os, sqlite3, subprocess, sys

fails, warns, oks = [], [], []
def OK(m): oks.append(m); print(f"OK  {m}", flush=True)
def FAIL(m): fails.append(m); print(f"FAIL {m}", flush=True)
def WARN(m): warns.append(m); print(f"WARN {m}", flush=True)
def sh(cmd, timeout=90):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=timeout)

print("======== SEPIDZ SYSTEM ========", flush=True)
ver = open("/usr/local/share/claude-client/connect-version.txt").read().strip()
(OK if ver=="20260717.33" else FAIL)(f"version={ver}")
cm = open("/usr/local/lib/claude-mount").read()
(OK if "Only remote User settings" in cm and "_apply_git_scm_policy" in cm else FAIL)("claude-mount git policy")
cr = open("/usr/local/bin/laptop-exec","rb").read().count(b"\r")
(OK if cr==0 else FAIL)(f"system laptop-exec CR={cr}")
sud = open("/etc/sudoers.d/claude-client-deploy").read()
(OK if "sepidz" in sud and "NOPASSWD" in sud and "smart" in sud else FAIL)("sudoers smart+sepidz NOPASSWD")
GOLD = open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
OK(f"golden mid len={len(GOLD)}")

LIVE = {
    "farzadb": [("frontend", None), ("backend", None)],
    "hosseinm": [("sepidz-web", "Backend"), ("sepidz-web", "Frontend")],  # (mount, git_subdir)
    "hosseinb": [("frontend", None)],
    "nimaz": [],
}

print("======== LIVE USERS ========", flush=True)
for user, projs in LIVE.items():
    home = f"/home/{user}"
    conf = {}
    confp = f"{home}/.claude-connect.conf"
    if os.path.isfile(confp):
        for line in open(confp, errors="ignore"):
            if "=" in line and not line.startswith("#"):
                k,v = line.strip().split("=",1); conf[k.upper()] = v
    port = conf.get("TUNNEL_PORT","")
    gm = conf.get("GIT_MODE","?")
    up = False
    if port:
        up = sh(f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'").returncode == 0
    print(f"--- {user} GIT_MODE={gm} port={port} tunnel={'UP' if up else 'DOWN'} ---", flush=True)
    if up: OK(f"{user} tunnel UP")
    else: WARN(f"{user} tunnel DOWN")

    sp = f"{home}/.cursor-server/data/User/settings.json"
    if os.path.isfile(sp):
        j = json.load(open(sp))
        (OK if j.get("git.enabled") is False else FAIL)(f"{user} remote git.enabled={j.get('git.enabled')}")
    else:
        (FAIL if up else WARN)(f"{user} no cursor User settings")

    for label,p in [("profile",f"{home}/.config/Cursor/machineid"),("server",f"{home}/.cursor-server/data/machineid")]:
        if not os.path.isfile(p):
            (FAIL if up else WARN)(f"{user} {label} mid missing"); continue
        raw=open(p,"rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
        (OK if raw==GOLD else FAIL)(f"{user} {label} mid")

    db=f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
    if os.path.isfile(db):
        c=sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        def gv(k):
            r=c.execute("select value from ItemTable where key=?",(k,)).fetchone()
            return "" if not r or r[0] is None else str(r[0])
        at,rt=gv("cursorAuth/accessToken"),gv("cursorAuth/refreshToken"); c.close()
        (OK if len(at)>20 and len(rt)>20 else FAIL)(f"{user} tokens at={len(at)} rt={len(rt)}")
    else:
        (FAIL if up else WARN)(f"{user} state.vscdb missing")

    le=f"{home}/.local/bin/laptop-exec"
    if os.path.isfile(le):
        (OK if open(le,"rb").read().count(b"\r")==0 else FAIL)(f"{user} laptop-exec CR=0")
    else:
        (FAIL if up else WARN)(f"{user} no laptop-exec")

    seen_io = set()
    for proj, git_sub in projs:
        mp=f"{home}/mounts/{proj}"
        if not os.path.isdir(mp):
            WARN(f"{user}/{proj} mount missing"); continue

        # .git check
        git_roots = []
        if git_sub:
            gp = os.path.join(mp, git_sub, ".git")
            if os.path.isdir(gp): git_roots.append(f"{proj}/{git_sub}")
        else:
            if os.path.isdir(os.path.join(mp,".git")): git_roots.append(proj)
        if git_roots:
            for gr in git_roots:
                headp = f"{home}/mounts/{gr}/.git/HEAD"
                head = open(headp).read().strip() if os.path.isfile(headp) else "?"
                OK(f"{user}/{gr} .git HEAD={head}")
        else:
            FAIL(f"{user}/{proj} .git missing")

        if not up: continue

        # IO once per mount project
        if proj not in seen_io:
            seen_io.add(proj)
            # IMPORTANT: keep $HOME expansion inside su login shell
            cmd = (
                f"su - {user} -c '"
                f"printf deepok > \"$HOME/.deep-src.txt\" && "
                f"laptop-exec write -p {proj} .deep-e2e.txt < \"$HOME/.deep-src.txt\" && "
                f"laptop-exec read -p {proj} .deep-e2e.txt && "
                f"rm -f \"$HOME/.deep-src.txt\" && "
                f"laptop-exec run -p {proj} -- cmd /c del .deep-e2e.txt"
                f"'"
            )
            r=sh(cmd)
            out=(r.stdout or "")+(r.stderr or "")
            (OK if "deepok" in out else FAIL)(f"{user}/{proj} IO" if "deepok" in out else f"{user}/{proj} IO: {out[:200]}")

        # git status for real git root via laptop-exec (cwd relative)
        if git_sub:
            # laptop-exec git is per project mount id; for monorepo run with -C if supported
            r=sh(
                f"su - {user} -c '"
                f"laptop-exec run -p {proj} -- git -C {git_sub} status -sb && "
                f"laptop-exec run -p {proj} -- git -C {git_sub} rev-parse --is-inside-work-tree"
                f"'",
                timeout=90,
            )
            label=f"{user}/{proj}/{git_sub}"
        else:
            r=sh(
                f"su - {user} -c '"
                f"laptop-exec git -p {proj} -- status -sb && "
                f"laptop-exec git -p {proj} -- rev-parse --is-inside-work-tree"
                f"'",
                timeout=90,
            )
            label=f"{user}/{proj}"
        out=((r.stdout or "")+(r.stderr or "")).strip()
        if r.returncode==0 and "true" in out:
            OK(f"{label} git OK :: {out.splitlines()[0]}")
        else:
            FAIL(f"{label} git: {out[:220]}")

print("======== SUMMARY ========", flush=True)
print(f"ok={len(oks)} warn={len(warns)} fail={len(fails)}", flush=True)
for f in fails: print(f"  FAIL: {f}", flush=True)
for w in warns: print(f"  WARN: {w}", flush=True)
print("DEEP_GREEN" if not fails else "DEEP_RED", flush=True)
sys.exit(1 if fails else 0)
