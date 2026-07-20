$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$nl = [char]10

# SEPIDZ: why no user connect logs + list .claude dirs
$pySep = @'
import os, pwd, glob, subprocess, json
from collections import Counter
print("=== SEPIDZ .claude presence ===")
for ent in sorted(pwd.getpwall(), key=lambda e:e.pw_name):
    if ent.pw_uid < 1000: continue
    home=ent.pw_dir
    cl=f"{home}/.claude"
    logs=f"{home}/.claude/logs"
    print(f"{ent.pw_name}: .claude={'Y' if os.path.isdir(cl) else 'N'} logs={'Y' if os.path.isdir(logs) else 'N'}", end="")
    if os.path.isdir(logs):
        files=sorted(glob.glob(logs+"/*"), key=os.path.getmtime, reverse=True)[:8]
        print(f" n={len(glob.glob(logs+'/*'))} newest={[os.path.basename(f) for f in files]}")
    else:
        print()
    # also check alternate locations
    for alt in (f"{home}/.local/share/claude/logs", f"{home}/claude-logs", f"{home}/.cursor-server/data/logs"):
        if os.path.isdir(alt):
            print(f"  ALT {alt}: {len(os.listdir(alt))} entries")

print("\n=== cron connect-logs cleanup ===")
for p in glob.glob("/etc/cron.d/claude*")+glob.glob("/etc/cron.d/*connect*"):
    print(p)
    print(open(p).read())

print("\n=== auth last OK vs FAIL timeline (no secrets) ===")
auth="/var/log/claude-auth.log"
ok=fail=0
first_fail=last_ok=None
ev=Counter()
with open(auth,"rb") as f:
    f.seek(0,2); f.seek(max(0,f.tell()-2_000_000))
    for ln in f.read().decode("utf-8","replace").splitlines():
        try: j=json.loads(ln)
        except: continue
        e=j.get("event")
        ev[e]+=1
        if e=="PROBE_OK" or (j.get("ok") is True):
            ok+=1; last_ok=j.get("timestamp")
        if e=="PROBE_FAIL":
            fail+=1
            if not first_fail: first_fail=j.get("timestamp")
print("events_tail2MB", dict(ev), "ok", ok, "fail", fail, "first_fail", first_fail, "last_ok", last_ok)

# sshfs mounts now
print("\n=== /proc/mounts sshfs ===")
for ln in open("/proc/mounts"):
    if "sshfs" in ln or "fuse" in ln and "/mounts/" in ln:
        print(ln.strip()[:200])
'@

# SMART: mine connect log for versions/errors
$pySmart = @'
import os, re, json
from collections import Counter
p="/home/smart/.claude/logs/connect-20260717.log"
print("=== SMART connect log stats ===")
print("size", os.path.getsize(p), "mtime", os.path.getmtime(p))
ver=Counter(); levels=Counter(); interesting=[]
# stream last 1.5MB and also scan for version across whole via grep-like chunks
with open(p,"rb") as f:
    data=f.read()
text=data.decode("utf-8","replace")
for m in re.finditer(r"20260717\.\d+", text):
    ver[m.group(0)] += 1
for m in re.finditer(r"\[(ERROR|WARN|FAIL|INFO|DEBUG|TRACE)\]", text):
    levels[m.group(1)] += 1
# extract lines with ERROR/WARN/version/update
for ln in text.splitlines():
    if re.search(r"\[ERROR\]|\[WARN\]|ConnectVersion|CONNECT_VERSION|20260717\.|auto-?update|UPDATE|GIT_MODE|mount.*(fail|error|stale)|Failed", ln, re.I):
        if "PERF[" in ln and "20260717" not in ln and "ERROR" not in ln and "WARN" not in ln:
            continue
        interesting.append(ln.strip()[:240])
print("versions", dict(ver))
print("levels", dict(levels))
print("\n--- interesting (last 40) ---")
for ln in interesting[-40:]:
    print(ln)
print("\n--- interesting (first 20 version/update) ---")
vu=[x for x in interesting if re.search(r"20260717|update|VERSION|version", x, re.I)]
for ln in vu[:20]:
    print(ln)
print("\n=== SMART auth summary ===")
auth="/var/log/claude-auth.log"
ev=Counter(); 
with open(auth,"rb") as f:
    f.seek(0,2); f.seek(max(0,f.tell()-1_500_000))
    for ln in f.read().decode("utf-8","replace").splitlines():
        try: j=json.loads(ln)
        except: continue
        ev[j.get("event")]+=1
print(dict(ev))
'@

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))

[IO.File]::WriteAllText("$env:TEMP\ls.py", $pySep)
scp -o BatchMode=yes -q "$env:TEMP\ls.py" 'sepidz@192.168.250.70:/tmp/ls.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/ls.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\ls.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\ls.sh" 'sepidz@192.168.250.70:/tmp/ls.sh'
Write-Host '#### SEPIDZ DEEPER ####'
ssh -o BatchMode=yes -o ConnectTimeout=20 sepidz@192.168.250.70 'bash /tmp/ls.sh'

[IO.File]::WriteAllText("$env:TEMP\lsmart.py", $pySmart)
scp -o BatchMode=yes -q "$env:TEMP\lsmart.py" 'smart@192.168.210.240:/tmp/lsmart.py'
Write-Host '#### SMART DEEPER ####'
$out="$env:TEMP\lsmart_out.txt"
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15','smart@192.168.210.240','sudo -n python3 /tmp/lsmart.py 2>/dev/null || python3 /tmp/lsmart.py') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
[void]$p.WaitForExit(120000)
Get-Content $out -Raw
