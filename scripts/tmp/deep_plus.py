#!/usr/bin/env python3
"""Deeper complete audit: code + live + Win/Mac matrix."""
import json, os, pwd, re, sqlite3, subprocess, sys, hashlib

fails, warns, oks, notes = [], [], [], []
def OK(m): oks.append(m); print(f"OK  {m}", flush=True)
def FAIL(m): fails.append(m); print(f"FAIL {m}", flush=True)
def WARN(m): warns.append(m); print(f"WARN {m}", flush=True)
def NOTE(m): notes.append(m); print(f"NOTE {m}", flush=True)

def sh(cmd, t=45):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=t)

print("=" * 64, flush=True)
print("A) LIVE SYSTEM DEPTH", flush=True)
print("=" * 64, flush=True)

# bins
for p, markers in [
    ("/usr/local/bin/claude-self-heal", ["_heal_stale_mounts", "_heal_bin_crlf_all", "_heal_cursor_git_off", "Never use mountpoint", "GIT_MODE=off"]),
    ("/usr/local/bin/claude-automount", ["claude-self-heal", "ACTIVE_MOUNT", "VSCODE_IPC_HOOK_CLI", "Still self-heal"]),
    ("/usr/local/bin/laptop-exec-setup", ["_ensure_cursor_git_off", "GOLDEN_HEAL", "claude-self-heal"]),
    ("/usr/local/lib/claude-mount", ["_apply_git_scm_policy", "Only remote User settings", '"git.enabled": False']),
    ("/usr/local/bin/laptop-exec", ['GIT_MODE="off"']),
]:
    if not os.path.isfile(p):
        FAIL(f"missing {p}"); continue
    raw = open(p, "rb").read()
    cr = raw.count(b"\r")
    (OK if cr == 0 else FAIL)(f"{p} CR={cr}")
    text = raw.decode("utf-8", errors="replace")
    for m in markers:
        (OK if m in text else FAIL)(f"{os.path.basename(p)} has {m!r}")

ver = open("/usr/local/share/claude-client/connect-version.txt").read().strip()
(OK if ver == "20260717.33" else FAIL)(f"sepidz_ver={ver}")

sud = open("/etc/sudoers.d/claude-client-deploy").read() if os.path.isfile("/etc/sudoers.d/claude-client-deploy") else ""
(OK if "NOPASSWD" in sud and "sepidz" in sud and "smart" in sud else FAIL)("sudoers dual")

GOLD = open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")

print("=" * 64, flush=True)
print("B) PER-USER DEEP (Win/Mac aware)", flush=True)
print("=" * 64, flush=True)

win_users, mac_users, unknown_os = [], [], []

for ent in sorted(pwd.getpwall(), key=lambda e: e.pw_name):
    if ent.pw_uid < 1000 or ent.pw_name in ("nobody", "nfsnobody"):
        continue
    u, home = ent.pw_name, ent.pw_dir
    if not os.path.isdir(home):
        continue
    if not (os.path.isdir(f"{home}/.cursor-server") or os.path.isfile(f"{home}/.claude-connect.conf")):
        continue

    conf = {}
    cp = f"{home}/.claude-connect.conf"
    if os.path.isfile(cp):
        for line in open(cp, errors="ignore"):
            if "=" in line and not line.startswith("#"):
                k, v = line.strip().split("=", 1)
                conf[k.upper()] = v.strip()

    los = (conf.get("LAPTOP_OS") or "").lower()
    gm = (conf.get("GIT_MODE") or "").lower()
    port = conf.get("TUNNEL_PORT", "")
    am = conf.get("ACTIVE_MOUNT", "")
    lu = conf.get("LAPTOP_USER", "")

    if los == "windows":
        win_users.append(u)
    elif los == "mac":
        mac_users.append(u)
    else:
        unknown_os.append(u)
        NOTE(f"{u}: LAPTOP_OS missing/unknown (will set on next connect)")

    up = bool(port) and sh(f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'").returncode == 0
    print(f"\n--- {u} OS={los or '?'} MODE={gm or '?'} user={lu} :{port} {'UP' if up else 'DOWN'} active={am} ---", flush=True)

    # heal binary present for user
    for binname in ("claude-self-heal", "claude-automount", "laptop-exec", "laptop-exec-setup"):
        p = f"{home}/.local/bin/{binname}"
        if os.path.isfile(p):
            cr = open(p, "rb").read().count(b"\r")
            (OK if cr == 0 else FAIL)(f"{u} {binname} CR={cr}")
            st = os.stat(p)
            owner = pwd.getpwuid(st.st_uid).pw_name
            (OK if owner == u else FAIL)(f"{u} {binname} owner={owner}")
        else:
            (WARN if up else NOTE)(f"{u} missing ~/.local/bin/{binname}")

    # run heal dry (already quiet) as user and capture
    r = sh(f"sudo -u {u} -H /usr/local/bin/claude-self-heal 2>&1", t=60)
    if r.returncode != 0:
        FAIL(f"{u} heal exit={r.returncode}: {(r.stdout or '')[:150]}")
    else:
        OK(f"{u} heal runs")

    # Cursor git
    sp = f"{home}/.cursor-server/data/User/settings.json"
    if os.path.isfile(sp):
        j = json.load(open(sp))
        if gm in ("server", "on", "yes", "1", "slow"):
            NOTE(f"{u} server-mode git.enabled={j.get('git.enabled')}")
        elif j.get("git.enabled") is False and "git.path" not in j:
            OK(f"{u} Cursor git OFF")
        else:
            FAIL(f"{u} Cursor git bad {j.get('git.enabled')} path={j.get('git.path')}")
    elif up:
        WARN(f"{u} no cursor settings while UP")

    # mid/tokens
    for label, p in [("profile", f"{home}/.config/Cursor/machineid"), ("server", f"{home}/.cursor-server/data/machineid")]:
        if not os.path.isfile(p):
            (WARN if up else NOTE)(f"{u} {label} mid missing"); continue
        raw = open(p, "rb").read().replace(b"\r", b"").replace(b"\n", b"").strip().strip(b"\"'")
        (OK if raw == GOLD else FAIL)(f"{u} {label} mid")

    db = f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
    if os.path.isfile(db):
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        def gv(k):
            r = c.execute("select value from ItemTable where key=?", (k,)).fetchone()
            return "" if not r or r[0] is None else str(r[0])
        at, rt = gv("cursorAuth/accessToken"), gv("cursorAuth/refreshToken")
        c.close()
        (OK if len(at) > 20 and len(rt) > 20 else FAIL)(f"{u} tokens at={len(at)} rt={len(rt)}")
    elif up:
        WARN(f"{u} no state.vscdb")

    # mounts / git integrity for UP users
    mroot = f"{home}/mounts"
    mounted = []
    if os.path.isdir(mroot):
        try:
            for mid in sorted(os.listdir(mroot)):
                mp = f"{mroot}/{mid}"
                if any(f" {mp} " in ln for ln in open("/proc/mounts")):
                    mounted.append(mid)
        except Exception as e:
            WARN(f"{u} mounts list {e}")

    if mounted and not up:
        FAIL(f"{u} STALE mounts {mounted} with tunnel DOWN")
    elif mounted:
        OK(f"{u} mounted={mounted}")

    # deep git for known live projects
    if up:
        projects = []
        if u == "farzadb":
            projects = [("frontend", None), ("backend", None)]
        elif u == "hosseinm":
            projects = [("sepidz-web", "Backend"), ("sepidz-web", "Frontend")]
        elif u == "hosseinb":
            projects = [("frontend", None)]
        for proj, sub in projects:
            if sub:
                gp = f"{home}/mounts/{proj}/{sub}/.git"
                label = f"{u}/{proj}/{sub}"
            else:
                gp = f"{home}/mounts/{proj}/.git"
                label = f"{u}/{proj}"
            if os.path.isdir(gp):
                head = open(f"{gp}/HEAD").read().strip() if os.path.isfile(f"{gp}/HEAD") else "?"
                OK(f"{label} .git HEAD={head}")
                # hide residue
                if os.path.isdir(os.path.join(os.path.dirname(gp), ".git.server-session")) and gm == "off":
                    WARN(f"{label} hide residue with off")
            else:
                WARN(f"{label} .git missing on mount")

            # laptop-exec git
            if sub:
                cmd = f"su - {u} -c 'laptop-exec run -p {proj} -- git -C {sub} rev-parse --is-inside-work-tree && laptop-exec run -p {proj} -- git -C {sub} status -sb'"
            else:
                cmd = f"su - {u} -c 'laptop-exec git -p {proj} -- rev-parse --is-inside-work-tree && laptop-exec git -p {proj} -- status -sb'"
            r = sh(cmd, t=90)
            out = ((r.stdout or "") + (r.stderr or "")).strip()
            if r.returncode == 0 and "true" in out:
                OK(f"{label} laptop-exec git OK :: {out.splitlines()[0]}")
            else:
                FAIL(f"{label} git: {out[:200]}")

            # IO
            if not sub:  # once per mount id
                cmd = (
                    f"su - {u} -c '"
                    f"printf deepplus > \"$HOME/.dp-src.txt\" && "
                    f"laptop-exec write -p {proj} .dp-e2e.txt < \"$HOME/.dp-src.txt\" && "
                    f"laptop-exec read -p {proj} .dp-e2e.txt && "
                    f"rm -f \"$HOME/.dp-src.txt\" && "
                    f"laptop-exec run -p {proj} -- cmd /c del .dp-e2e.txt"
                    f"'"
                )
                r = sh(cmd, t=90)
                out = (r.stdout or "") + (r.stderr or "")
                (OK if "deepplus" in out else FAIL)(f"{u}/{proj} IO" if "deepplus" in out else f"{u}/{proj} IO {out[:150]}")

print("=" * 64, flush=True)
print("C) WIN/MAC COVERAGE", flush=True)
print("=" * 64, flush=True)
NOTE(f"windows_os_users={win_users}")
NOTE(f"mac_os_users={mac_users}")
NOTE(f"unknown_os_users={unknown_os}")
if not mac_users:
    NOTE("no live LAPTOP_OS=mac session online now — Mac path covered in code/publish; will activate on next Mac connect")
else:
    OK(f"live Mac users present: {mac_users}")

# bashrc automount hooks
print("=" * 64, flush=True)
print("D) BASHRC / LOGIN HOOKS", flush=True)
print("=" * 64, flush=True)
for ent in pwd.getpwall():
    if ent.pw_uid < 1000:
        continue
    br = f"{ent.pw_dir}/.bashrc"
    if os.path.isfile(br):
        t = open(br, errors="ignore").read()
        if "claude-automount" in t:
            OK(f"{ent.pw_name} .bashrc has automount")
        elif os.path.isfile(f"{ent.pw_dir}/.claude-connect.conf"):
            WARN(f"{ent.pw_name} has connect conf but no automount in .bashrc")

print("=" * 64, flush=True)
print("SUMMARY", flush=True)
print("=" * 64, flush=True)
print(f"ok={len(oks)} warn={len(warns)} fail={len(fails)} note={len(notes)}", flush=True)
for f in fails:
    print(f"  FAIL: {f}", flush=True)
for w in warns:
    print(f"  WARN: {w}", flush=True)
print("DEEP_PLUS_GREEN" if not fails else "DEEP_PLUS_RED", flush=True)
sys.exit(1 if fails else 0)
