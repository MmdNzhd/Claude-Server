#!/usr/bin/env python3
"""Deeper edge-case audit beyond deep_plus."""
import json, os, pwd, re, socket, subprocess, time

ok = warn = fail = note = 0
warns, fails = [], []

def OK(m):
    global ok; ok += 1; print(f"OK  {m}", flush=True)
def WARN(m):
    global warn; warn += 1; warns.append(m); print(f"WARN {m}", flush=True)
def FAIL(m):
    global fail; fail += 1; fails.append(m); print(f"FAIL {m}", flush=True)
def NOTE(m):
    global note; note += 1; print(f"NOTE {m}", flush=True)

def sh(cmd, t=30):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t)

def section(t):
    print(f"\n{'='*64}\n{t}\n{'='*64}", flush=True)

# ---- A) System binaries: markers + no CRLF + no mountpoint hang ----
section("A) SYSTEM BINS / HANG GUARDS")
for path, must in [
    ("/usr/local/bin/claude-self-heal", ["_heal_missing_user_bins", "Never use mountpoint", "GIT_MODE"]),
    ("/usr/local/bin/claude-automount", ["claude-self-heal", "Still self-heal", "ACTIVE_MOUNT"]),
    ("/usr/local/bin/laptop-exec-setup", ["Keep setup itself in PATH", "claude-self-heal", "_ensure_cursor_git_off"]),
    ("/usr/local/bin/laptop-exec", ["ControlPersist", 'GIT_MODE="off"']),
    ("/usr/local/bin/claude-mount", ['GIT_MODE="off"', "_apply_git_scm_policy"]),
]:
    if not os.path.isfile(path):
        FAIL(f"missing {path}"); continue
    raw = open(path, "rb").read()
    cr = raw.count(b"\r")
    (OK if cr == 0 else FAIL)(f"{path} CR={cr}")
    txt = raw.decode("utf-8", "replace")
    for m in must:
        (OK if m in txt else FAIL)(f"{os.path.basename(path)} has '{m}'")
    # hang guard: active (non-comment) mountpoint -q is a hang risk on frozen SSHFS
    bad = []
    for i, line in enumerate(txt.splitlines(), 1):
        s = line.lstrip()
        if s.startswith("#"):
            continue
        if "mountpoint -q" in line:
            bad.append(i)
    if bad:
        FAIL(f"{path} uses mountpoint -q at lines {bad[:8]} (hang risk)")
    else:
        OK(f"{os.path.basename(path)} no active mountpoint -q")

# ---- B) Sudoers deploy ----
section("B) SUDOERS / DEPLOY PATH")
sud = "/etc/sudoers.d/claude-client-deploy"
if os.path.isfile(sud):
    t = open(sud).read()
    (OK if "NOPASSWD" in t else WARN)("sudoers has NOPASSWD")
    OK(f"sudoers present ({len(t)} bytes)")
else:
    WARN("no /etc/sudoers.d/claude-client-deploy")

# ---- C) Per-user deep ----
section("C) PER-USER EDGE CASES")
proc_mounts = open("/proc/mounts").read()
human = [e for e in pwd.getpwall() if e.pw_uid >= 1000 and e.pw_name not in ("nobody", "nfsnobody")]
live_up = []
for ent in sorted(human, key=lambda e: e.pw_name):
    u, home = ent.pw_name, ent.pw_dir
    if not os.path.isdir(home):
        continue
    conf_p = f"{home}/.claude-connect.conf"
    has_cursor = os.path.isdir(f"{home}/.cursor-server")
    if not (has_cursor or os.path.isfile(conf_p)):
        continue
    conf = {}
    if os.path.isfile(conf_p):
        for line in open(conf_p, encoding="utf-8", errors="replace"):
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip().strip('"').strip("'")
    port = conf.get("TUNNEL_PORT") or conf.get("PORT") or ""
    gm = (conf.get("GIT_MODE") or "").lower()
    los = (conf.get("LAPTOP_OS") or "").lower()
    am = conf.get("ACTIVE_MOUNT") or ""
    up = False
    if port.isdigit():
        try:
            s = socket.create_connection(("127.0.0.1", int(port)), 1.5)
            s.close(); up = True
        except OSError:
            up = False
    if up:
        live_up.append(u)
    print(f"\n--- {u} OS={los or '?'} MODE={gm or '?'} :{port or '-'} {'UP' if up else 'DOWN'} active={am or '-'} ---", flush=True)

    # bins + owner + CR + executable
    for bn in ("claude-self-heal", "claude-automount", "laptop-exec", "laptop-exec-setup"):
        p = f"{home}/.local/bin/{bn}"
        if not os.path.isfile(p):
            (FAIL if up else WARN)(f"{u} missing {bn}")
            continue
        raw = open(p, "rb").read()
        cr = raw.count(b"\r")
        (OK if cr == 0 else FAIL)(f"{u} {bn} CR={cr}")
        st = os.stat(p)
        owner = pwd.getpwuid(st.st_uid).pw_name
        (OK if owner == u else FAIL)(f"{u} {bn} owner={owner}")
        (OK if (st.st_mode & 0o111) else FAIL)(f"{u} {bn} executable")
        if not raw.startswith(b"#!"):
            WARN(f"{u} {bn} missing shebang")

    # GIT_MODE normalized
    if gm in ("",):
        (WARN if up else NOTE)(f"{u} GIT_MODE empty")
    elif gm not in ("off", "hide", "server", "on", "yes", "1", "slow"):
        FAIL(f"{u} weird GIT_MODE={gm!r}")
    else:
        OK(f"{u} GIT_MODE={gm}")

    # Cursor settings git off
    sp = f"{home}/.cursor-server/data/User/settings.json"
    if os.path.isfile(sp):
        try:
            j = json.load(open(sp))
        except Exception as e:
            FAIL(f"{u} settings.json parse: {e}"); j = {}
        if gm in ("server", "on", "yes", "1", "slow"):
            NOTE(f"{u} server-mode git.enabled={j.get('git.enabled')}")
        else:
            if j.get("git.enabled") is False and "git.path" not in j:
                OK(f"{u} Cursor git OFF")
            else:
                FAIL(f"{u} Cursor git not OFF: enabled={j.get('git.enabled')} path={j.get('git.path')}")
    elif has_cursor:
        WARN(f"{u} missing Cursor User settings.json")

    # no git shim
    shim = f"{home}/.local/bin/git-via-laptop-exec"
    (OK if not os.path.exists(shim) else FAIL)(f"{u} no git shim")

    # stale SSHFS when tunnel DOWN: mounts under home/mounts must not linger
    mounts_home = f"{home}/mounts"
    stale = []
    for line in proc_mounts.splitlines():
        parts = line.split()
        if len(parts) < 3: continue
        mnt = parts[1]
        fstype = parts[2]
        if mnt.startswith(mounts_home + "/") and fstype in ("fuse.sshfs", "fuse"):
            if not up:
                stale.append(mnt)
    if stale:
        FAIL(f"{u} stale SSHFS while tunnel DOWN: {stale}")
    else:
        OK(f"{u} no stale SSHFS (tunnel {'UP' if up else 'DOWN'})")

    # .bashrc automount
    brc = f"{home}/.bashrc"
    if os.path.isfile(brc):
        t = open(brc, encoding="utf-8", errors="replace").read()
        (OK if "claude-automount" in t else WARN)(f"{u} .bashrc automount")
    else:
        NOTE(f"{u} no .bashrc")

    # heal idempotent
    r = sh(f"sudo -u {u} -H /usr/local/bin/claude-self-heal --quiet 2>&1", t=90)
    (OK if r.returncode == 0 else FAIL)(f"{u} heal rc={r.returncode}")

    # after heal, setup must exist (self-heal refresh)
    p = f"{home}/.local/bin/laptop-exec-setup"
    (OK if os.path.isfile(p) else FAIL)(f"{u} setup present after heal")

# ---- D) Edge: heal restores deleted setup ----
section("D) EDGE: HEAL RESTORES DELETED SETUP BIN")
if live_up:
    u = live_up[0]
    home = pwd.getpwnam(u).pw_dir
    target = f"{home}/.local/bin/laptop-exec-setup"
    bak = target + ".bak_ultra"
    if os.path.isfile(target):
        os.rename(target, bak)
        r = sh(f"sudo -u {u} -H /usr/local/bin/claude-self-heal --quiet 2>&1", t=90)
        restored = os.path.isfile(target) and os.access(target, os.X_OK)
        (OK if r.returncode == 0 and restored else FAIL)(f"{u} heal restored deleted laptop-exec-setup")
        if not restored and os.path.isfile(bak):
            os.rename(bak, target)
        elif os.path.isfile(bak):
            os.remove(bak)
    else:
        WARN(f"{u} no setup to delete for restore test")
else:
    NOTE("no live UP user for restore test")

# ---- E) PATH sanity for live users ----
section("E) PATH CONTAINS ~/.local/bin")
for u in live_up:
    r = sh(f"sudo -u {u} -H bash -lc 'echo $PATH'", t=15)
    path = (r.stdout or "").strip()
    if f"/home/{u}/.local/bin" in path or "$HOME/.local/bin" in path or "/.local/bin" in path:
        OK(f"{u} PATH has .local/bin")
    else:
        # still OK if login profile adds it later; warn only
        WARN(f"{u} PATH may miss .local/bin: {path[:120]}")

# ---- F) Versions ----
section("F) VERSIONS")
# local sepidz bundle version if present
for p in ("/usr/local/share/claude-client/connect-version.txt",):
    if os.path.isfile(p):
        v = open(p).read().strip()
        OK(f"sepidz connect-version={v}")
    else:
        NOTE("no sepidz connect-version.txt")

print(f"\nNOTE live_up={live_up}")
section("SUMMARY")
print(f"ok={ok} warn={warn} fail={fail} note={note}")
for w in warns: print(f"  WARN: {w}")
for f in fails: print(f"  FAIL: {f}")
if fail == 0:
    print("DEEP_ULTRA_GREEN")
else:
    print("DEEP_ULTRA_RED")
    raise SystemExit(1)
