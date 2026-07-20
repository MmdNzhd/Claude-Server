#!/usr/bin/env python3
"""Systematic Sepidz health matrix. Exit 1 on fail."""
import json, os, sqlite3, subprocess, sys

fails, warns, oks = [], [], []
def OK(m): oks.append(m); print(f"OK  {m}", flush=True)
def FAIL(m): fails.append(m); print(f"FAIL {m}", flush=True)
def WARN(m): warns.append(m); print(f"WARN {m}", flush=True)
def sh(cmd, timeout=90):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=timeout)

print("======== A) SYSTEM ========", flush=True)
ver = open("/usr/local/share/claude-client/connect-version.txt").read().strip()
(OK if ver == "20260717.33" else FAIL)(f"bundle_version={ver}")

cm = open("/usr/local/lib/claude-mount").read()
(OK if "_apply_git_scm_policy" in cm and "Only remote User settings" in cm else FAIL)("claude-mount SCM policy")
(OK if '"git.enabled": False' in cm or "'git.enabled': False" in cm else FAIL)("claude-mount disables git.enabled")
(OK if "git-via-laptop-exec" not in cm else FAIL)("no git shim in mount policy")

cr = open("/usr/local/bin/laptop-exec", "rb").read().count(b"\r")
(OK if cr == 0 else FAIL)(f"system laptop-exec CR={cr}")
(OK if not os.path.isfile("/usr/local/bin/git-via-laptop-exec") else FAIL)("no system git shim binary")

sud = open("/etc/sudoers.d/claude-client-deploy").read()
(OK if "sepidz" in sud and "smart" in sud and "NOPASSWD" in sud else FAIL)("sudoers smart+sepidz")

GOLD = open("/etc/cursor-auth/golden/machine-id.txt", "rb").read().replace(b"\r", b"").replace(b"\n", b"").strip().strip(b"\"'")
OK(f"golden_mid len={len(GOLD)}")

LIVE = {
    "farzadb": ["frontend", "backend"],
    "hosseinm": ["sepidz-web"],
    "hosseinb": ["frontend"],
    "nimaz": [],
}

print("======== B) LIVE USERS ========", flush=True)
for user, projs in LIVE.items():
    home = f"/home/{user}"
    conf = {}
    cp = f"{home}/.claude-connect.conf"
    if os.path.isfile(cp):
        for line in open(cp, errors="ignore"):
            if "=" in line and not line.startswith("#"):
                k, v = line.strip().split("=", 1)
                conf[k.upper()] = v
    port = conf.get("TUNNEL_PORT", "")
    gm = conf.get("GIT_MODE", "?")
    up = bool(port) and sh(f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'").returncode == 0
    print(f"--- {user} GIT_MODE={gm} :{port} {'UP' if up else 'DOWN'} ---", flush=True)
    if up: OK(f"{user} tunnel")
    else: WARN(f"{user} tunnel DOWN")

    # Cursor git must be OFF
    sp = f"{home}/.cursor-server/data/User/settings.json"
    if os.path.isfile(sp):
        j = json.load(open(sp))
        if j.get("git.enabled") is False and j.get("git.autoRepositoryDetection") is False and "git.path" not in j:
            OK(f"{user} Cursor git OFF")
        else:
            FAIL(f"{user} Cursor git settings bad: enabled={j.get('git.enabled')} path={j.get('git.path')}")
    else:
        (FAIL if up else WARN)(f"{user} no User settings.json")

    # mid + tokens
    for label, p in [("profile", f"{home}/.config/Cursor/machineid"), ("server", f"{home}/.cursor-server/data/machineid")]:
        if not os.path.isfile(p):
            (FAIL if up else WARN)(f"{user} {label} mid missing"); continue
        raw = open(p, "rb").read().replace(b"\r", b"").replace(b"\n", b"").strip().strip(b"\"'")
        (OK if raw == GOLD else FAIL)(f"{user} {label} mid")

    db = f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
    if os.path.isfile(db):
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        def gv(k):
            r = c.execute("select value from ItemTable where key=?", (k,)).fetchone()
            return "" if not r or r[0] is None else str(r[0])
        at, rt = gv("cursorAuth/accessToken"), gv("cursorAuth/refreshToken")
        c.close()
        (OK if len(at) > 20 and len(rt) > 20 else FAIL)(f"{user} tokens at={len(at)} rt={len(rt)}")
    else:
        (FAIL if up else WARN)(f"{user} state.vscdb missing")

    le = f"{home}/.local/bin/laptop-exec"
    if os.path.isfile(le):
        (OK if open(le, "rb").read().count(b"\r") == 0 else FAIL)(f"{user} LE CR=0")
    else:
        (FAIL if up else WARN)(f"{user} no LE")
    if os.path.isfile(f"{home}/.local/bin/git-via-laptop-exec"):
        FAIL(f"{user} unexpected git shim")

    for proj in projs:
        mp = f"{home}/mounts/{proj}"
        if not os.path.isdir(mp):
            WARN(f"{user}/{proj} mount missing"); continue
        # .git may exist on disk — fine; Cursor ignores it
        has_git = os.path.isdir(os.path.join(mp, ".git"))
        nested = any(os.path.isdir(os.path.join(mp, s, ".git")) for s in ("Backend", "Frontend", "backend", "frontend"))
        if has_git or nested:
            OK(f"{user}/{proj} .git on disk (Cursor ignores)")
        else:
            WARN(f"{user}/{proj} no .git visible")

        if not up:
            continue
        cmd = (
            f"su - {user} -c '"
            f"printf sysok > \"$HOME/.sys-src.txt\" && "
            f"laptop-exec write -p {proj} .sys-e2e.txt < \"$HOME/.sys-src.txt\" && "
            f"laptop-exec read -p {proj} .sys-e2e.txt && "
            f"rm -f \"$HOME/.sys-src.txt\" && "
            f"laptop-exec run -p {proj} -- cmd /c del .sys-e2e.txt"
            f"'"
        )
        r = sh(cmd)
        out = (r.stdout or "") + (r.stderr or "")
        (OK if "sysok" in out else FAIL)(f"{user}/{proj} IO" if "sysok" in out else f"{user}/{proj} IO: {out[:180]}")

print("======== SUMMARY ========", flush=True)
print(f"ok={len(oks)} warn={len(warns)} fail={len(fails)}", flush=True)
for f in fails: print(f"  FAIL: {f}", flush=True)
for w in warns: print(f"  WARN: {w}", flush=True)
print("SYS_GREEN" if not fails else "SYS_RED", flush=True)
sys.exit(1 if fails else 0)
