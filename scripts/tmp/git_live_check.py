import os, json, subprocess
users = ["farzadb", "hosseinm", "hosseinb", "nimaz"]
print("LIVE_MOUNT_GIT_CHECK", flush=True)
cm = open("/usr/local/lib/claude-mount").read()
print("policy_fn", "_apply_git_scm_policy" in cm, flush=True)
print("policy_calls", cm.count("_apply_git_scm_policy"), flush=True)

def conf_git_mode(u):
    p = f"/home/{u}/.claude-connect.conf"
    if not os.path.isfile(p):
        return "?"
    for line in open(p, errors="ignore"):
        if line.upper().startswith("GIT_MODE="):
            return line.split("=",1)[1].strip()
    return "?"

def check_settings(path, label):
    vs = os.path.join(path, ".vscode", "settings.json")
    gitp = os.path.join(path, ".git")
    gits = os.path.join(path, ".git.server-session")
    print(f"  {label}: .git={os.path.exists(gitp)} .git.ss={os.path.exists(gits)} settings={os.path.exists(vs)}", flush=True)
    if os.path.exists(vs):
        try:
            j = json.loads(open(vs, encoding="utf-8").read())
            print(f"    git.enabled={j.get('git.enabled')} autoRepo={j.get('git.autoRepositoryDetection')}", flush=True)
        except Exception as e:
            print(f"    json_err={e}", flush=True)

for u in users:
    home = f"/home/{u}"
    if not os.path.isdir(home):
        continue
    print(f"--- {u} GIT_MODE={conf_git_mode(u)}", flush=True)
    mroot = f"{home}/mounts"
    if not os.path.isdir(mroot):
        continue
    # only list dir names, no deep walk
    try:
        mounts = sorted(os.listdir(mroot))
    except Exception as e:
        print(f"  listdir_err={e}", flush=True)
        continue
    for mid in mounts:
        mp = os.path.join(mroot, mid)
        if not os.path.isdir(mp):
            continue
        check_settings(mp, mid)
        # shallow one level only
        try:
            kids = os.listdir(mp)
        except Exception as e:
            print(f"  {mid} list_err={e}", flush=True)
            continue
        for kid in kids:
            if kid.startswith("."):
                continue
            sp = os.path.join(mp, kid)
            if not os.path.isdir(sp):
                continue
            if os.path.isdir(os.path.join(sp, ".git")) or os.path.isdir(os.path.join(sp, ".vscode")):
                check_settings(sp, f"{mid}/{kid}")
print("DONE", flush=True)
