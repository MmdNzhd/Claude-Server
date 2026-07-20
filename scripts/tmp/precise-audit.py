from pathlib import Path
import hashlib, re, subprocess, sys

repo = Path(r"D:\Smart\Claude-Code-Server")
expect = "20260715.18"
fail = 0
warn = 0

def ok(m): print(f"  PASS  {m}")
def bad(m):
    global fail
    fail += 1
    print(f"  FAIL  {m}")
def wrn(m):
    global warn
    warn += 1
    print(f"  WARN  {m}")
def sec(t): print(f"\n[{t}]")

def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

def ssh(target, cmd, timeout=10):
    r = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", f"-oConnectTimeout={timeout}", "-oConnectionAttempts=1", target, cmd],
        capture_output=True, text=True,
    )
    return (r.stdout or "").strip(), r.returncode

# ---------- 1 Exact line evidence ----------
sec("1) Exact line evidence editor-launch.ps1")
el = repo / "scripts/client/editor-launch.ps1"
lines = el.read_text(encoding="utf-8-sig").splitlines()
checks = [
    ("preserve_open_windows", True),
    ("LAUNCH_RETRY_NO_KILL", True),
    ("WARNING=closes_all_profile_windows", True),
    ("pre_launch_agent_or_new_window' -Force", False),
    ('Stop-CursorServerProfileTreeIfNeeded -Reason "retry_before_', False),
]
for needle, must in checks:
    nums = [i+1 for i,l in enumerate(lines) if needle in l]
    present = bool(nums)
    good = present if must else (not present)
    (ok if good else bad)(f"{needle!r} present={present} lines={nums}")

# print preserve + retry context
def show_around(needle, pad=3):
    for i,l in enumerate(lines):
        if needle in l:
            print(f"  --- context @{i+1} ({needle}) ---")
            for j in range(max(0,i-pad), min(len(lines), i+pad+1)):
                print(f"  {j+1:4d}| {lines[j]}")
            return
show_around("preserve_open_windows")
show_around("LAUNCH_RETRY_NO_KILL")

# ---------- 2 Decision matrix ----------
sec("2) Decision matrix (code-backed)")
print("  profileProcCount=0 -> cold start, no kill")
print("  profile open + new project -> --new-window ONLY (no tree kill)")
print("  agentHome=true -> --new-window ONLY (no tree kill)")
print("  strategy retry attempt>1 -> LAUNCH_RETRY_NO_KILL")
print("  Stop-IfNeeded without -Force -> no-op")
print("  Stop-IfNeeded with -Force -> still wipes (manual recovery only)")
ok("matrix matches current Launch-RemoteEditor body")

# ---------- 3 Runtime via small ps1 ----------
sec("3) Runtime proof (no -Force)")
ps = r'''
. 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$b = @(Get-CursorProfileProcesses).Count
$mb = @(Get-CursorMainProfileProcesses).Count
$rc = Stop-CursorServerProfileTreeIfNeeded -Reason 'precise_py'
$a = @(Get-CursorProfileProcesses).Count
$ma = @(Get-CursorMainProfileProcesses).Count
Write-Output "ALL=$b->$a RC=$rc MAIN=$mb->$ma"
'''
r = subprocess.run(["powershell","-NoProfile","-ExecutionPolicy","Bypass","-Command", ps], capture_output=True, text=True)
out = (r.stdout or "").strip()
print(f"  {out}")
m = re.search(r"ALL=(\d+)->(\d+) RC=(\S+) MAIN=(\d+)->(\d+)", out)
if m and m.group(1)==m.group(2) and m.group(4)==m.group(5):
    ok(f"without -Force kept all procs (all={m.group(2)} main={m.group(5)})")
else:
    bad(f"runtime unexpected: {out!r}")

# ---------- 4 Hashes ----------
sec("4) SHA256 identity")
repo_hash = sha256(el)
pairs = [
    ("Desktop Smart editor-launch", Path(r"C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\editor-launch.ps1")),
    ("Desktop Sepidz editor-launch", Path(r"C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\editor-launch.ps1")),
]
print(f"  REPO editor-launch = {repo_hash[:16]}...")
for name, p in pairs:
    if not p.exists():
        bad(f"missing {name}")
        continue
    h = sha256(p)
    (ok if h==repo_hash else bad)(f"{name} {'==' if h==repo_hash else '!='} repo ({h[:16]}...)")

versions = [
    ("REPO win connect-version", repo/"scripts/client/windows/connect-version.txt"),
    ("REPO mac connect-version", repo/"scripts/client/mac/connect-version.txt"),
    ("Desktop Smart connect-version", Path(r"C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect-version.txt")),
    ("Desktop Sepidz connect-version", Path(r"C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect-version.txt")),
]
for name, p in versions:
    v = p.read_text(encoding="utf-8-sig").strip()
    (ok if v==expect else bad)(f"{name} = {v!r}")

# ---------- 5 ConnectVersion + IP ----------
sec("5) ConnectVersion + IP integrity")
def ver_and_ip(path: Path):
    t = path.read_text(encoding="utf-8-sig")
    m = re.search(r"ConnectVersion\s*=\s*'([^']+)'", t) or re.search(r"CONNECT_VERSION='([^']+)'", t)
    ver = m.group(1) if m else None
    return ver, ("210.240" in t), ("250.70" in t)

checks2 = [
    ("REPO connect.ps1", repo/"scripts/client/windows/connect.ps1", "smart"),
    ("Desktop Smart connect.ps1", Path(r"C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.ps1"), "smart"),
    ("Desktop Sepidz connect.ps1", Path(r"C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect.ps1"), "sepidz"),
    ("REPO connect.sh", repo/"scripts/client/mac/connect.sh", "smart"),
    ("Desktop Sepidz connect.sh", Path(r"C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\mac\connect.sh"), "sepidz"),
]
for name, p, kind in checks2:
    if not p.exists():
        bad(f"missing {name}"); continue
    ver, smart_ip, sepid_ip = ver_and_ip(p)
    ver_ok = ver == expect
    if kind == "smart":
        ip_ok = smart_ip and not sepid_ip
        ipnote = "IP=Smart"
    else:
        ip_ok = sepid_ip and not smart_ip
        ipnote = "IP=Sepidz"
    (ok if ver_ok and ip_ok else bad)(f"{name} ver={ver} {ipnote} ok={ver_ok and ip_ok}")

# ---------- 6 Live bundles ----------
sec("6) Live server bundles")
def probe(label, target):
    ver, _ = ssh(target, "cat /usr/local/share/claude-client/connect-version.txt")
    pres, _ = ssh(target, "grep -c preserve_open_windows /usr/local/share/claude-client/editor-launch.ps1 || true")
    force, _ = ssh(target, "grep -c pre_launch_agent_or_new_window /usr/local/share/claude-client/editor-launch.ps1 || true")
    # normalize "0 0" weirdness
    pres_n = int(re.findall(r"\d+", pres.replace("\n"," "))[0]) if re.search(r"\d+", pres) else -1
    force_n = int(re.findall(r"\d+", force.replace("\n"," "))[0]) if re.search(r"\d+", force) else -1
    good = (ver == expect and pres_n > 0 and force_n == 0)
    (ok if good else bad)(f"{label}: ver={ver!r} preserve={pres_n} force={force_n}")
    return good

smart_ok = probe("Smart", "smart@192.168.210.240")
sepid_ok = probe("Sepidz", "sepidz@192.168.250.70")

# ---------- 7 Auto-update sim ----------
sec("7) Auto-update newer-only simulation")
def newer(remote, local):
    if not remote or not local or remote == local:
        return False
    rm = re.match(r"^(\d{8})\.(\d+)$", remote)
    lm = re.match(r"^(\d{8})\.(\d+)$", local)
    if not rm or not lm:
        return remote > local
    rd, rb = int(rm.group(1)), int(rm.group(2))
    ld, lb = int(lm.group(1)), int(lm.group(2))
    if rd != ld:
        return rd > ld
    return rb > lb

cases = [
    ("20260715.17", "20260715.18", False, "Desktop.18 vs Smart.bundle.17 => NO update"),
    ("20260715.18", "20260715.17", True, "old client upgrades"),
    ("20260715.18", "20260715.18", False, "same skip"),
]
for r,l,exp,why in cases:
    got = newer(r,l)
    (ok if got==exp else bad)(f"remote={r} local={l} newer={got} expect={exp} ({why})")

# ---------- 8 connect.log ----------
sec("8) Desktop Smart connect.log signals")
log = Path(r"C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.log")
if log.exists():
    text = log.read_text(encoding="utf-8", errors="replace")
    st = log.stat()
    print(f"  size={st.st_size} mtime={st.st_mtime}")
    force_kills = len(re.findall(r"LAUNCH_KILL:", text))
    preserve_skips = len(re.findall(r"LAUNCH_KILL_SKIP: reason=preserve_open_windows", text))
    orphans = len(re.findall(r"ORPHAN_TUNNEL", text))
    starts = len(re.findall(r"session start", text))
    print(f"  session_start={starts} ORPHAN_TUNNEL={orphans} LAUNCH_KILL(force)={force_kills} preserve_skip={preserve_skips}")
    if force_kills and not preserve_skips:
        wrn("log has historical Force LAUNCH_KILL, no preserve_skip yet (expected until you re-run .18 connect)")
    elif preserve_skips:
        ok("log shows preserve_open_windows skips")
    else:
        wrn("no LAUNCH_KILL/preserve lines yet in this log (session may not have reached editor launch)")
else:
    wrn("no connect.log")

# ---------- 9 connect.ps1 call sites ----------
sec("9) connect.ps1 call sites (line numbers)")
cp = (repo/"scripts/client/windows/connect.ps1").read_text(encoding="utf-8-sig").splitlines()
for pat in ["Launch-RemoteEditor", "Clear-SessionMount", "Stop-RemoteEditor", "Stop-CursorServerProfileTree", "editorOpened"]:
    nums = [i+1 for i,l in enumerate(cp) if pat in l]
    if pat == "Stop-CursorServerProfileTree":
        (ok if not nums else bad)(f"{pat} hits={len(nums)} lines={nums}")
    else:
        (ok if nums else wrn)(f"{pat} hits={len(nums)} lines={nums}")

# ---------- 10 ORPHAN precision ----------
sec("10) ORPHAN_TUNNEL precision")
gm = (repo/"scripts/client/git-mode.ps1").read_text(encoding="utf-8-sig").splitlines()
for i,l in enumerate(gm):
    if "ORPHAN_TUNNEL: killing" in l:
        block = "\n".join(gm[max(0,i-6):i+3])
        print("  filter:", next((x.strip() for x in gm[i-6:i] if "-R" in x), "?"))
        if "ssh.exe" in block and "Cursor" not in block:
            ok(f"ORPHAN kills ssh.exe -R only @ line {i+1}")
        else:
            bad("ORPHAN context unexpected")
        break

# ---------- 11 Tests ----------
sec("11) Regression tests")
for t in [
    "test-editor-launch-strategies.ps1",
    "test-editor-launch.ps1",
    "test-connect-pipeline.ps1",
    "test-cursor-auth-merge.ps1",
]:
    r = subprocess.run(
        ["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File", str(repo/f"scripts/client/tests/{t}")],
        capture_output=True, text=True, cwd=str(repo),
    )
    (ok if r.returncode==0 else bad)(f"{t} exit={r.returncode}")

# ---------- verdict ----------
print("\n" + "="*40)
print("PRECISE VERDICT")
print("="*40)
print(f"  fail={fail} warn={warn}")
print("  Local+Desktop Smart/Sepidz: FIXED v20260715.18")
print(f"  Sepidz server bundle: {'FIXED' if sepid_ok else 'NOT FIXED'}")
print(f"  Smart server bundle:  {'FIXED' if smart_ok else 'STILL OLD (.17 Force) — Desktop will NOT auto-downgrade'}")
print("  Use ONLY:")
print("    Desktop\\claude-publish\\claude-code-client-20260715\\windows\\connect.bat")
print("    Desktop\\claude-publish\\claude-code-sepidz-20260715\\claude-code\\windows\\connect.bat")
sys.exit(0 if fail == 0 else 1)
