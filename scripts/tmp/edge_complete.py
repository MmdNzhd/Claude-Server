#!/usr/bin/env python3
"""Complete live edge-case catalog for Sepidz (+ notes for Smart)."""
import json, os, pwd, sqlite3, subprocess, time, glob

rows = []  # (severity, id, status, detail)
def add(cat, eid, status, detail):
    rows.append((cat, eid, status, detail))
    print(f"[{status}] {cat}/{eid}: {detail}", flush=True)

def sh(cmd, t=20):
    try:
        return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=t)
    except Exception as e:
        class R: pass
        r=R(); r.returncode=99; r.stdout=""; r.stderr=str(e)
        return r

# -------- SYSTEM --------
cm = open("/usr/local/lib/claude-mount").read()
su = open("/usr/local/bin/laptop-exec-setup").read()
le = open("/usr/local/bin/laptop-exec","rb").read()
ver = open("/usr/local/share/claude-client/connect-version.txt").read().strip()
sud = open("/etc/sudoers.d/claude-client-deploy").read() if os.path.isfile("/etc/sudoers.d/claude-client-deploy") else ""

add("SYS", "bundle_ver", "OK" if ver=="20260717.33" else "FAIL", f"sepidz={ver}")
add("SYS", "le_crlf", "OK" if le.count(b"\r")==0 else "FAIL", f"CR={le.count(b'\\r')}")
add("SYS", "sudoers", "OK" if "NOPASSWD" in sud and "sepidz" in sud and "smart" in sud else "FAIL", "claude-client-deploy")
add("SYS", "scm_policy", "OK" if "_apply_git_scm_policy" in cm and '"git.enabled": False' in cm else "FAIL", "mount git-off")
add("SYS", "setup_git_off", "OK" if "_ensure_cursor_git_off" in su else "FAIL", "login reinforce")
add("SYS", "no_shim", "OK" if not os.path.isfile("/usr/local/bin/git-via-laptop-exec") else "FAIL", "shim absent")

# code structural edges (documented)
add("CODE", "trusted_hide_skip_warm", "NOTE", "already-mounted + trusted + hide may skip _warm_sshfs_cache; git-off still via setup")
add("CODE", "ide_skip_automount", "NOTE", "VSCODE_IPC_HOOK_CLI/CURSOR_AGENT skips automount by design")
add("CODE", "tunnel_down_restore", "NOTE", "GIT_MODE=off cannot restore .git if tunnel down — warns reconnect")
add("CODE", "tunnel_down_hide", "NOTE", "GIT_MODE=hide cannot rename .git if tunnel down — warns")
add("CODE", "sshfs_host_key", "NOTE", "host key change → actionable error with ssh-keygen -R hint")
add("CODE", "sshfs_perm_denied", "NOTE", "key auth fail → re-run connect.bat")
add("CODE", "sshfs_path_missing", "NOTE", "laptop path not found")
add("CODE", "sshfs_timeout", "NOTE", "laptop SSH not responding")
add("CODE", "hide_remount_loop", "NOTE", "hide + stale SSHFS .git triggers remount once; skip if hide failed")
add("CODE", "server_mode_remount", "NOTE", "GIT_MODE=server remounts to see restored .git")
add("CODE", "off_already_mounted", "NOTE", "already mounted + off → restore stubs + warm (git-off)")
add("CODE", "automount_stamp_300s", "NOTE", "stamp <300s + check ok: hide/server exit early; off still runs up")
add("CODE", "automount_active_only", "NOTE", "only ACTIVE_MOUNT mounts on login, never all projects")
add("CODE", "recover_on_login", "NOTE", "automount runs recover before up")
add("CODE", "deploy_all_uids", "NOTE", "deploy-laptop-exec iterates getent uid>=1000")
add("CODE", "crlf_strip_deploy", "NOTE", "sed CRLF strip system + per-user LE")
add("OPS", "smart_freeze_22", "NOTE", "Smart stay 20260717.22 until tonight publish; then clients update")
add("OPS", "sepidz_33", "OK" if ver=="20260717.33" else "FAIL", "Sepidz live .33")
add("OPS", "downloads_zip", "NOTE", "old Downloads connect copy / elevated admin can miss update or wrong path")
add("OPS", "reload_after_auth", "NOTE", "after auth sync users need Reload Window")
add("OPS", "git_ui_off_intentional", "NOTE", "Cursor SCM disabled; .git on disk intact; use laptop-exec git if needed")

GOLD = open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")

# -------- USERS --------
for ent in sorted(pwd.getpwall(), key=lambda e: e.pw_name):
    if ent.pw_uid < 1000 or ent.pw_name in ("nobody","nfsnobody"):
        continue
    u, home = ent.pw_name, ent.pw_dir
    if not os.path.isdir(home):
        continue
    has_cursor = os.path.isdir(f"{home}/.cursor-server")
    confp = f"{home}/.claude-connect.conf"
    if not has_cursor and not os.path.isfile(confp):
        continue

    conf = {}
    if os.path.isfile(confp):
        for line in open(confp, errors="ignore"):
            if "=" in line and not line.startswith("#"):
                k,v = line.strip().split("=",1); conf[k.upper()]=v
    else:
        add("USER", f"{u}.no_conf", "NOTE", "cursor present but never/no connect conf")
        continue

    gm = conf.get("GIT_MODE", "")
    port = conf.get("TUNNEL_PORT", "")
    am = conf.get("ACTIVE_MOUNT", "")
    los = conf.get("LAPTOP_OS", "")
    lu = conf.get("LAPTOP_USER", "")
    up = bool(port) and sh(f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'").returncode==0

    if not gm:
        add("USER", f"{u}.git_mode_empty", "NOTE", f"GIT_MODE missing in conf (defaults off); laptop={lu} os={los}")
    elif gm not in ("off","hide","server"):
        add("USER", f"{u}.git_mode_weird", "WARN", f"GIT_MODE={gm!r}")
    else:
        add("USER", f"{u}.git_mode", "OK", gm)

    add("USER", f"{u}.tunnel", "OK" if up else "NOTE", f":{port} {'UP' if up else 'DOWN'} active={am}")

    # mounts vs tunnel
    mroot = f"{home}/mounts"
    mounts, mounted = [], []
    if os.path.isdir(mroot):
        try: mounts = sorted(os.listdir(mroot))
        except Exception as e: add("USER", f"{u}.mounts_list", "WARN", str(e))
    for mid in mounts:
        mp = f"{mroot}/{mid}"
        try:
            if any(mp in ln for ln in open("/proc/mounts")):
                mounted.append(mid)
        except Exception:
            pass
    if mounted and not up:
        add("USER", f"{u}.stale_mount", "WARN", f"mounted={mounted} tunnel DOWN — SSHFS may hang IO until reconnect/umount")
    if up and am and am not in mounts:
        add("USER", f"{u}.active_missing", "WARN", f"ACTIVE_MOUNT={am} not under mounts/ {mounts}")
    if up and am and am not in mounted and am in mounts:
        add("USER", f"{u}.active_unmounted", "NOTE", f"ACTIVE_MOUNT={am} dir exists but not mounted")

    # git cursor
    sp = f"{home}/.cursor-server/data/User/settings.json"
    if os.path.isfile(sp):
        j = json.load(open(sp))
        if gm in ("server","on","yes","1","slow"):
            add("USER", f"{u}.cursor_git", "NOTE", f"server mode; enabled={j.get('git.enabled')}")
        elif j.get("git.enabled") is False and "git.path" not in j:
            add("USER", f"{u}.cursor_git", "OK", "OFF")
        else:
            add("USER", f"{u}.cursor_git", "FAIL", f"enabled={j.get('git.enabled')} path={j.get('git.path')}")
        # ownership
        st = os.stat(sp)
        owner = pwd.getpwuid(st.st_uid).pw_name
        add("USER", f"{u}.settings_owner", "OK" if owner==u else "FAIL", owner)
    elif up:
        add("USER", f"{u}.cursor_git", "WARN", "no User/settings.json while online")

    # LE
    lep = f"{home}/.local/bin/laptop-exec"
    if os.path.isfile(lep):
        cr = open(lep,"rb").read().count(b"\r")
        add("USER", f"{u}.le_crlf", "OK" if cr==0 else "FAIL", f"CR={cr}")
        st = os.stat(lep)
        owner = pwd.getpwuid(st.st_uid).pw_name
        add("USER", f"{u}.le_owner", "OK" if owner==u else "FAIL", owner)
    else:
        add("USER", f"{u}.le", "WARN" if up else "NOTE", "missing ~/.local/bin/laptop-exec")

    # auth
    for label,p in [("profile",f"{home}/.config/Cursor/machineid"),("server",f"{home}/.cursor-server/data/machineid")]:
        if not os.path.isfile(p):
            add("USER", f"{u}.mid_{label}", "WARN" if up else "NOTE", "missing")
            continue
        raw=open(p,"rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
        add("USER", f"{u}.mid_{label}", "OK" if raw==GOLD else "FAIL", f"match={raw==GOLD}")

    db=f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
    if os.path.isfile(db):
        c=sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        def gv(k):
            r=c.execute("select value from ItemTable where key=?",(k,)).fetchone()
            return "" if not r or r[0] is None else str(r[0])
        at,rt=gv("cursorAuth/accessToken"),gv("cursorAuth/refreshToken")
        email=gv("cursorAuth/cachedEmail")
        c.close()
        add("USER", f"{u}.tokens", "OK" if len(at)>20 and len(rt)>20 else ("FAIL" if up else "WARN"), f"at={len(at)} rt={len(rt)}")
        if not email:
            add("USER", f"{u}.cachedEmail", "NOTE", "empty (golden often empty; WARN-only historically)")
    elif up:
        add("USER", f"{u}.tokens", "WARN", "no state.vscdb")

    # .git hide residue / pollution for mounted
    for mid in mounted[:8]:
        mp = f"{mroot}/{mid}"
        # root
        if os.path.isdir(os.path.join(mp,".git.server-session")) and not os.path.exists(os.path.join(mp,".git")):
            if gm == "off":
                add("USER", f"{u}.{mid}.hide_residue", "WARN", ".git.server-session while GIT_MODE=off")
            else:
                add("USER", f"{u}.{mid}.hide", "NOTE", "hidden as expected for hide mode")
        vs = os.path.join(mp, ".vscode", "settings.json")
        if os.path.isfile(vs):
            try:
                sj=json.load(open(vs,encoding="utf-8"))
                gk={k:sj[k] for k in sj if str(k).startswith("git.")}
                if gk:
                    add("USER", f"{u}.{mid}.ws_git", "WARN", f"workspace git.*={gk}")
            except Exception as e:
                add("USER", f"{u}.{mid}.ws_git", "NOTE", f"parse {e}")
        # nested one level
        try:
            for name in os.listdir(mp):
                if name.startswith("."): continue
                p=os.path.join(mp,name)
                if not os.path.isdir(p): continue
                if os.path.isdir(os.path.join(p,".git.server-session")) and not os.path.exists(os.path.join(p,".git")) and gm=="off":
                    add("USER", f"{u}.{mid}.{name}.hide_residue", "WARN", "nested hide residue while off")
        except Exception:
            pass

    # stamp
    stamp=f"{home}/.cache/claude-automount.stamp"
    if os.path.isfile(stamp):
        age=int(time.time()-os.path.getmtime(stamp))
        add("USER", f"{u}.automount_stamp", "NOTE", f"age_s={age}")

# -------- CLIENT/PRODUCT edges (static knowledge) --------
for eid, detail in [
    ("connect_elevated", "connect.bat self-elevates; LAPTOP_USER from interactive session not elevated token"),
    ("foreign_session", "Warn-ForeignServerSession + self-heal stale foreign session"),
    ("script_push_nonfatal", "script push fail does not abort connect (PushOk tracking)"),
    ("update_unreachable", "connect-update logs unreachable / up to date (not silent)"),
    ("update_version_compare", "client updates only when server connect-version.txt newer"),
    ("git_mode_off_default", "default GIT_MODE=off; laptop-exec git for server-side git"),
    ("git_mode_hide", "renames .git→.git.server-session on laptop; Cursor sees no .git"),
    ("git_mode_server", "keeps .git on SSHFS; slow; Cursor git left alone by policy"),
    ("multi_project", "down-others / ACTIVE_MOUNT prevents mounting all projects"),
    ("mux_disabled", "claude-mount disables SSH mux to laptop"),
    ("mac_path", "LAPTOP_OS=mac uses different hide/stub paths"),
    ("windows_encodedcommand", "Windows git hide uses PowerShell EncodedCommand"),
    ("auth_merge_not_replace", "cursor-auth-laptop merges tokens; never closes Cursor"),
    ("partial_auth", "historically tokens-only without mid — now mid checked"),
    ("golden_email_empty", "cachedEmail/stripe often empty server-wide — WARN only"),
    ("probe_tmp_perm", "root-created /tmp probes can false-fail; use $HOME"),
    ("sshfs_hang_listdir", "deep os.walk on SSHFS can hang — audits must stay shallow"),
    ("sudo_from_laptop_sepidz", "sudo-from-laptop --sepidz weaker; prefer laptop SSH+base64"),
    ("zip_backslash", "Windows CreateFromDirectory broke mac/connect.sh — fixed forward-slash zip"),
]:
    add("PRODUCT", eid, "NOTE", detail)

# summary
from collections import Counter
c=Counter(r[2] for r in rows)
print("\n======== COMPLETE SUMMARY ========", flush=True)
print(f"total={len(rows)} OK={c['OK']} WARN={c['WARN']} FAIL={c['FAIL']} NOTE={c['NOTE']}", flush=True)
for st in ("FAIL","WARN"):
    for cat,eid,status,detail in rows:
        if status==st:
            print(f"  {st}: {cat}/{eid}: {detail}", flush=True)
print("EDGE_COMPLETE_GREEN" if c["FAIL"]==0 else "EDGE_COMPLETE_RED", flush=True)
raise SystemExit(0 if c["FAIL"]==0 else 1)
