#!/usr/bin/env python3
"""Very deep git audit on Sepidz. Does not modify repos except read-only probes via laptop-exec."""
import json, os, sqlite3, subprocess, sys, stat

fails, warns, oks, info = [], [], [], []

def OK(m): oks.append(m); print(f"OK  {m}", flush=True)
def FAIL(m): fails.append(m); print(f"FAIL {m}", flush=True)
def WARN(m): warns.append(m); print(f"WARN {m}", flush=True)
def INFO(m): info.append(m); print(f"INFO {m}", flush=True)

def sh(cmd, timeout=90):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=timeout)

print("=" * 60, flush=True)
print("1) SYSTEM GIT POLICY", flush=True)
print("=" * 60, flush=True)

cm = open("/usr/local/lib/claude-mount").read()
checks = [
    ("_apply_git_scm_policy present", "_apply_git_scm_policy" in cm),
    ("Only remote User settings", "Only remote User settings" in cm),
    ("git.enabled False in policy", '"git.enabled": False' in cm),
    ("autoRepositoryDetection False", '"git.autoRepositoryDetection": False' in cm),
    ("no git-via-laptop-exec shim", "git-via-laptop-exec" not in cm),
    ("GIT_MODE=off supported", 'GIT_MODE="off"' in cm or "GIT_MODE=off" in cm),
    ("_hide_git present", "_hide_git" in cm),
    ("_restore_git present", "_restore_git" in cm or "_restore_git_body" in cm),
]
for name, ok in checks:
    (OK if ok else FAIL)(f"mount:{name}")

# count policy call sites
OK(f"mount:_apply_git_scm_policy calls={cm.count('_apply_git_scm_policy')}")

# live version
ver = open("/usr/local/share/claude-client/connect-version.txt").read().strip()
OK(f"sepidz_bundle={ver}")

GOLD = open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")

USERS = {
    "farzadb": {
        "mounts": ["frontend", "backend"],
        "git_roots": [("frontend", None), ("backend", None)],
    },
    "hosseinm": {
        "mounts": ["sepidz-web"],
        "git_roots": [("sepidz-web", "Backend"), ("sepidz-web", "Frontend")],
    },
    "hosseinb": {
        "mounts": ["frontend"],
        "git_roots": [("frontend", None)],
    },
    "nimaz": {
        "mounts": [],
        "git_roots": [],
    },
}

def read_conf(home):
    d = {}
    p = f"{home}/.claude-connect.conf"
    if not os.path.isfile(p):
        return d
    for line in open(p, errors="ignore"):
        if "=" in line and not line.startswith("#"):
            k,v = line.strip().split("=",1)
            d[k.upper()] = v
    return d

def inspect_git_dir(path, label):
    """Deep inspect a .git directory."""
    if not os.path.exists(path):
        FAIL(f"{label} MISSING")
        return None
    if os.path.islink(path):
        WARN(f"{label} is symlink -> {os.readlink(path)}")
    if os.path.isfile(path):
        try:
            content = open(path).read().strip()
            INFO(f"{label} is FILE (gitdir?): {content[:120]!r}")
            if content.startswith("gitdir:"):
                WARN(f"{label} gitdir pointer file")
            return {"type": "file", "content": content}
        except Exception as e:
            FAIL(f"{label} file read err {e}")
            return None
    if not os.path.isdir(path):
        FAIL(f"{label} not dir/file")
        return None

    st = os.lstat(path)
    mode = oct(st.st_mode)
    try:
        entries = sorted(os.listdir(path))
    except Exception as e:
        FAIL(f"{label} listdir err {e}")
        return None

    required = ["HEAD", "config", "objects", "refs"]
    missing = [r for r in required if r not in entries]
    if missing:
        FAIL(f"{label} missing critical: {missing}")
    else:
        OK(f"{label} structure OK entries={len(entries)} mode={mode}")

    head = None
    hp = os.path.join(path, "HEAD")
    if os.path.isfile(hp):
        head = open(hp).read().strip()
        INFO(f"{label} HEAD={head}")

    cfg = os.path.join(path, "config")
    remote = None
    if os.path.isfile(cfg):
        try:
            txt = open(cfg, errors="ignore").read()
            for line in txt.splitlines():
                if "url =" in line or "url=" in line:
                    remote = line.strip()
                    break
            INFO(f"{label} remote={remote or '(none found)'}")
        except Exception as e:
            WARN(f"{label} config read {e}")

    # objects sanity
    obj = os.path.join(path, "objects")
    obj_count = 0
    pack_count = 0
    if os.path.isdir(obj):
        for root, dirs, files in os.walk(obj):
            if "pack" in root.replace("\\","/").split("/"):
                pack_count += len([f for f in files if f.endswith(".pack")])
            obj_count += len(files)
            if obj_count > 8000:
                break
    INFO(f"{label} objects~={obj_count} packs~={pack_count}")

    # index
    idx = os.path.join(path, "index")
    if os.path.isfile(idx):
        OK(f"{label} index size={os.path.getsize(idx)}")
    else:
        WARN(f"{label} no index")

    return {"type": "dir", "head": head, "entries": entries, "mode": mode}

print("=" * 60, flush=True)
print("2) PER-USER DEEP", flush=True)
print("=" * 60, flush=True)

for user, spec in USERS.items():
    home = f"/home/{user}"
    if not os.path.isdir(home):
        FAIL(f"{user} home missing")
        continue
    conf = read_conf(home)
    gm = conf.get("GIT_MODE", "?")
    port = conf.get("TUNNEL_PORT", "")
    am = conf.get("ACTIVE_MOUNT", "")
    up = bool(port) and sh(f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'").returncode == 0
    print(f"\n--- {user} GIT_MODE={gm} ACTIVE={am} :{port} tunnel={'UP' if up else 'DOWN'} ---", flush=True)

    if gm not in ("off", "hide", "server"):
        WARN(f"{user} unusual GIT_MODE={gm}")
    else:
        OK(f"{user} GIT_MODE={gm}")

    # Cursor settings — must be fully off
    sp = f"{home}/.cursor-server/data/User/settings.json"
    if os.path.isfile(sp):
        j = json.load(open(sp))
        ge = j.get("git.enabled")
        ar = j.get("git.autoRepositoryDetection")
        gp = j.get("git.path")
        scan = j.get("git.repositoryScanMaxDepth")
        INFO(f"{user} cursor settings git.enabled={ge} autoRepo={ar} path={gp} scanDepth={scan}")
        if ge is False and ar is False and gp is None:
            OK(f"{user} Cursor git fully OFF")
        else:
            FAIL(f"{user} Cursor git NOT fully off: {ge=} {ar=} {gp=}")
        # also list any other git.* keys
        git_keys = {k: j[k] for k in j if k.startswith("git.")}
        INFO(f"{user} all git.* keys={git_keys}")
    else:
        (FAIL if up else WARN)(f"{user} no cursor User/settings.json")

    # vscode-server too
    vp = f"{home}/.vscode-server/data/User/settings.json"
    if os.path.isfile(vp):
        j = json.load(open(vp))
        if j.get("git.enabled") is False:
            OK(f"{user} vscode-server git OFF")
        else:
            WARN(f"{user} vscode-server git.enabled={j.get('git.enabled')}")

    # shim must not exist
    if os.path.isfile(f"{home}/.local/bin/git-via-laptop-exec"):
        FAIL(f"{user} git shim present (should be removed)")
    else:
        OK(f"{user} no git shim")

    # LE CRLF
    le = f"{home}/.local/bin/laptop-exec"
    if os.path.isfile(le):
        cr = open(le,"rb").read().count(b"\r")
        (OK if cr==0 else FAIL)(f"{user} laptop-exec CR={cr}")

    # list mounts
    mroot = f"{home}/mounts"
    if os.path.isdir(mroot):
        try:
            mounts = sorted(os.listdir(mroot))
        except Exception as e:
            mounts = []; WARN(f"{user} mounts list err {e}")
        INFO(f"{user} mounts dirs={mounts}")

    # inspect each git root
    for proj, sub in spec["git_roots"]:
        base = f"{home}/mounts/{proj}"
        if sub:
            root = os.path.join(base, sub)
            label = f"{user}/{proj}/{sub}"
        else:
            root = base
            label = f"{user}/{proj}"

        if not os.path.isdir(root):
            WARN(f"{label} path missing")
            continue

        gitp = os.path.join(root, ".git")
        gits = os.path.join(root, ".git.server-session")
        INFO(f"{label} .git={os.path.exists(gitp)} .git.ss={os.path.exists(gits)}")

        if os.path.exists(gits) and not os.path.exists(gitp):
            WARN(f"{label} HIDDEN as .git.server-session (hide mode residue?)")
            inspect_git_dir(gits, f"{label}/.git.server-session")
        elif os.path.exists(gitp):
            inspect_git_dir(gitp, f"{label}/.git")
        else:
            # scan one level for nested
            found = False
            try:
                for name in os.listdir(root):
                    if name.startswith("."): continue
                    p = os.path.join(root, name)
                    if os.path.isdir(os.path.join(p, ".git")):
                        inspect_git_dir(os.path.join(p, ".git"), f"{label}/{name}/.git")
                        found = True
            except Exception as e:
                WARN(f"{label} nested scan {e}")
            if not found:
                WARN(f"{label} no .git found")

        # workspace settings pollution?
        vs = os.path.join(root, ".vscode", "settings.json")
        if os.path.isfile(vs):
            try:
                sj = json.load(open(vs, encoding="utf-8"))
                git_ws = {k: sj[k] for k in sj if k.startswith("git.")}
                if git_ws:
                    WARN(f"{label} workspace git.* still set: {git_ws}")
                else:
                    OK(f"{label} workspace settings clean of git.*")
            except Exception as e:
                WARN(f"{label} vscode settings parse {e}")

        # live git via laptop-exec if tunnel up
        if not up:
            WARN(f"{label} skip laptop-exec git (tunnel down)")
            continue

        if sub:
            cmd = (
                f"su - {user} -c '"
                f"laptop-exec run -p {proj} -- git -C {sub} rev-parse --is-inside-work-tree && "
                f"laptop-exec run -p {proj} -- git -C {sub} status -sb && "
                f"laptop-exec run -p {proj} -- git -C {sub} log -1 --oneline && "
                f"laptop-exec run -p {proj} -- git -C {sub} rev-parse HEAD"
                f"'"
            )
        else:
            cmd = (
                f"su - {user} -c '"
                f"laptop-exec git -p {proj} -- rev-parse --is-inside-work-tree && "
                f"laptop-exec git -p {proj} -- status -sb && "
                f"laptop-exec git -p {proj} -- log -1 --oneline && "
                f"laptop-exec git -p {proj} -- rev-parse HEAD"
                f"'"
            )
        r = sh(cmd, timeout=120)
        out = ((r.stdout or "") + (r.stderr or "")).strip()
        if r.returncode == 0 and "true" in out:
            lines = [ln for ln in out.splitlines() if ln.strip()]
            OK(f"{label} laptop-exec git HEALTHY")
            for ln in lines[:5]:
                INFO(f"  {ln}")
        else:
            FAIL(f"{label} laptop-exec git FAIL: {out[:300]}")

        # fsck light: cat-file -t HEAD
        if sub:
            r2 = sh(f"su - {user} -c 'laptop-exec run -p {proj} -- git -C {sub} cat-file -t HEAD'", timeout=60)
        else:
            r2 = sh(f"su - {user} -c 'laptop-exec git -p {proj} -- cat-file -t HEAD'", timeout=60)
        t = ((r2.stdout or "") + (r2.stderr or "")).strip()
        if "commit" in t:
            OK(f"{label} HEAD object type=commit")
        else:
            FAIL(f"{label} HEAD cat-file: {t[:120]}")

print("=" * 60, flush=True)
print("3) OTHER USERS QUICK SCAN", flush=True)
print("=" * 60, flush=True)
# any other users with mounts + cursor
for ent_name in sorted(os.listdir("/home")):
    if ent_name in USERS or ent_name in ("lost+found",):
        continue
    home = f"/home/{ent_name}"
    if not os.path.isdir(home):
        continue
    sp = f"{home}/.cursor-server/data/User/settings.json"
    if not os.path.isfile(sp):
        continue
    j = json.load(open(sp))
    ge = j.get("git.enabled")
    if ge is False:
        OK(f"other:{ent_name} Cursor git OFF")
    else:
        WARN(f"other:{ent_name} Cursor git.enabled={ge}")

print("=" * 60, flush=True)
print("SUMMARY", flush=True)
print("=" * 60, flush=True)
print(f"ok={len(oks)} warn={len(warns)} fail={len(fails)} info={len(info)}", flush=True)
for f in fails:
    print(f"  FAIL: {f}", flush=True)
for w in warns:
    print(f"  WARN: {w}", flush=True)
print("GIT_DEEP_GREEN" if not fails else "GIT_DEEP_RED", flush=True)
sys.exit(1 if fails else 0)
