#!/usr/bin/env python3
"""Deep Sepidz health: system + live users. Exit 1 on any fail."""
import json, os, pwd, subprocess, sys, time

fails = []
oks = []

def ok(msg):
    oks.append(msg)
    print(f"OK  {msg}", flush=True)

def fail(msg):
    fails.append(msg)
    print(f"FAIL {msg}", flush=True)

def warn(msg):
    print(f"WARN {msg}", flush=True)

# --- system ---
ver_path = "/usr/local/share/claude-client/connect-version.txt"
try:
    ver = open(ver_path).read().strip()
    if ver == "20260717.33":
        ok(f"sepidz_version={ver}")
    else:
        fail(f"sepidz_version={ver} expected 20260717.33")
except Exception as e:
    fail(f"sepidz_version read: {e}")

cm = open("/usr/local/lib/claude-mount").read()
if "Only remote User settings" in cm and "_apply_git_scm_policy" in cm:
    ok("claude-mount git SCM user policy")
else:
    fail("claude-mount missing git SCM user policy")

le = open("/usr/local/bin/laptop-exec", "rb").read()
cr = le.count(b"\r")
if cr == 0:
    ok("system laptop-exec CR=0")
else:
    fail(f"system laptop-exec CR={cr}")

# sudoers
sud = "/etc/sudoers.d/claude-client-deploy"
if os.path.isfile(sud):
    s = open(sud).read()
    if "sepidz" in s and "install-client-bundle" in s:
        ok("sudoers claude-client-deploy has sepidz")
    else:
        fail("sudoers missing sepidz/install-client-bundle")
else:
    fail("sudoers claude-client-deploy missing")

# bundle present
bundle_dir = "/usr/local/share/claude-client"
for name in ("connect-version.txt",):
    p = os.path.join(bundle_dir, name)
    if os.path.isfile(p):
        ok(f"bundle {name}")
    else:
        fail(f"bundle missing {name}")

# look for windows zip / package markers
for cand in (
    "/usr/local/share/claude-client/windows",
    "/usr/local/share/claude-client/client",
    "/var/lib/claude-client",
):
    if os.path.isdir(cand):
        ok(f"bundle_dir {cand}")
        break

LIVE = ["farzadb", "hosseinm", "hosseinb", "nimaz"]

def read_conf(home):
    p = os.path.join(home, ".claude-connect.conf")
    d = {}
    if not os.path.isfile(p):
        return d
    for line in open(p, errors="ignore"):
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            d[k.strip().upper()] = v.strip()
    return d

def tunnel_up(port):
    if not port:
        return False
    try:
        r = subprocess.run(
            ["bash", "-c", f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'"],
            capture_output=True,
        )
        return r.returncode == 0
    except Exception:
        return False

def check_tokens(home):
    # common cursor auth locations
    cands = [
        os.path.join(home, ".cursor-server/data/User/globalStorage/state.vscdb"),
        os.path.join(home, ".cursor/argv.json"),
    ]
    # look for access token files used by sync
    token_ok = False
    at_len = rt_len = 0
    # search known token json paths
    for rel in (
        ".config/cursor/auth.json",
        ".cursor-server/data/User/globalStorage/cursor.auth.json",
        ".local/share/cursor/auth.json",
    ):
        p = os.path.join(home, rel)
        if os.path.isfile(p):
            try:
                j = json.load(open(p))
                at = j.get("accessToken") or j.get("access_token") or ""
                rt = j.get("refreshToken") or j.get("refresh_token") or ""
                at_len, rt_len = len(at), len(rt)
                if at_len >= 20 and rt_len >= 20:
                    token_ok = True
                    break
            except Exception:
                pass
    # also check machine id files
    mid_files = []
    for rel in (
        ".cursor-server/data/machineid",
        ".config/cursor/machineid",
        ".cursor/machineid",
    ):
        p = os.path.join(home, rel)
        if os.path.isfile(p):
            mid_files.append((rel, open(p).read().strip()[:64]))
    return token_ok, at_len, rt_len, mid_files

def check_user_git_settings(home):
    p = os.path.join(home, ".cursor-server/data/User/settings.json")
    if not os.path.isfile(p):
        return None
    try:
        j = json.load(open(p))
        return j.get("git.enabled") is False and j.get("git.autoRepositoryDetection") is False
    except Exception:
        return False

def probe_io(user, mount_rel):
    """Write/read/delete under mount using user's identity via a file in home first if mount slow — use home/.probe."""
    home = f"/home/{user}"
    mp = os.path.join(home, mount_rel)
    if not os.path.isdir(mp):
        return "missing"
    # probe in HOME not /tmp (root leftover perms)
    probe = os.path.join(home, f".claude_io_probe_{int(time.time()*1000)}")
    try:
        # write as root then chown — better: just check mount readable + writable via open in mount
        # Prefer mount root write of small file owned by user
        ent = pwd.getpwnam(user)
        testp = os.path.join(mp, f".claude_probe_{os.getpid()}")
        with open(testp, "w") as f:
            f.write("ok")
        os.chown(testp, ent.pw_uid, ent.pw_gid)
        data = open(testp).read()
        os.remove(testp)
        return "ok" if data == "ok" else "bad_content"
    except Exception as e:
        return f"err:{e}"

def check_user_le(home):
    p = os.path.join(home, ".local/bin/laptop-exec")
    if not os.path.isfile(p):
        return None
    return open(p, "rb").read().count(b"\r")

# golden mid compare helper
golden_mid = None
gpaths = [
    "/usr/local/share/claude-client/golden-machineid",
    "/usr/local/share/claude-client/machineid",
    "/etc/claude-server/golden-machineid",
]
for gp in gpaths:
    if os.path.isfile(gp):
        golden_mid = open(gp).read().strip()
        ok(f"golden_mid_source={gp} len={len(golden_mid)}")
        break
if not golden_mid:
    warn("no golden machineid file found (skip mid match)")

# known live mounts
USER_MOUNTS = {
    "farzadb": ["mounts/frontend", "mounts/backend"],
    "hosseinm": ["mounts/sepidz-web"],
    "hosseinb": ["mounts/frontend"],
    "nimaz": ["mounts/frontend"],
}

print("=== LIVE USERS ===", flush=True)
for user in LIVE:
    home = f"/home/{user}"
    if not os.path.isdir(home):
        fail(f"{user} home missing")
        continue
    conf = read_conf(home)
    gm = conf.get("GIT_MODE", "?")
    port = conf.get("TUNNEL_PORT", "")
    print(f"--- {user} GIT_MODE={gm} port={port}", flush=True)
    if gm not in ("off", "hide", "server", "?"):
        warn(f"{user} unusual GIT_MODE={gm}")

    up = tunnel_up(port)
    if up:
        ok(f"{user} tunnel UP :{port}")
    else:
        warn(f"{user} tunnel DOWN :{port}")

    git_set = check_user_git_settings(home)
    if git_set is True:
        ok(f"{user} remote git.enabled=false")
    elif git_set is False:
        fail(f"{user} remote git settings wrong")
    else:
        if up:
            fail(f"{user} missing cursor User settings.json")
        else:
            warn(f"{user} no cursor User settings (offline)")

    cr = check_user_le(home)
    if cr is None:
        warn(f"{user} no ~/.local/bin/laptop-exec")
    elif cr == 0:
        ok(f"{user} laptop-exec CR=0")
    else:
        fail(f"{user} laptop-exec CR={cr}")

    # machineid
    mid_p = os.path.join(home, ".cursor-server/data/machineid")
    if os.path.isfile(mid_p):
        mid = open(mid_p).read().strip()
        if mid:
            ok(f"{user} machineid len={len(mid)}")
            if golden_mid and mid != golden_mid:
                warn(f"{user} machineid != golden")
        else:
            fail(f"{user} machineid empty")
    else:
        if up:
            fail(f"{user} machineid missing")
        else:
            warn(f"{user} machineid missing (offline)")

    # IO on mounts if tunnel up or mount exists
    for rel in USER_MOUNTS.get(user, []):
        mp = os.path.join(home, rel)
        if not os.path.isdir(mp):
            warn(f"{user} {rel} not present")
            continue
        # skip deep IO if clearly not mounted (no entries / not mount)
        st = probe_io(user, rel)
        if st == "ok":
            ok(f"{user} {rel} IO")
        elif st == "missing":
            warn(f"{user} {rel} missing")
        else:
            # Permission on unmounted empty dir is soft warn
            if not up:
                warn(f"{user} {rel} IO {st} (tunnel down)")
            else:
                fail(f"{user} {rel} IO {st}")

print("=== SUMMARY ===", flush=True)
print(f"ok={len(oks)} fail={len(fails)}", flush=True)
for f in fails:
    print(f"  FAIL: {f}", flush=True)
sys.exit(1 if fails else 0)
