$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$nl = [char]10

$py = @'
#!/usr/bin/env python3
import os, pwd, glob, time, re, subprocess
from datetime import datetime

NOW = time.time()
HOST = os.uname().nodename

def section(t):
    print(f"\n{'='*72}\n{t}\n{'='*72}", flush=True)

def age(p):
    try:
        return NOW - os.path.getmtime(p)
    except OSError:
        return None

def tail_file(path, n=80, max_bytes=200_000):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            sz = f.tell()
            f.seek(max(0, sz - max_bytes))
            data = f.read()
        text = data.decode("utf-8", "replace")
        lines = text.splitlines()
        return lines[-n:], sz
    except Exception as e:
        return [f"<<read error: {e}>>"], 0

def interesting(line):
    keys = (
        "ERROR", "Error", "FAIL", "fail", "WARN", "warn", "TRACEBACK",
        "version", "VERSION", "20260717", "GIT_MODE", "mount", "sshfs",
        "stale", "heal", "CRLF", "timeout", "hang", "denied", "sudo",
        "tunnel", "UP", "DOWN", "connect", "auth", "fatal", "FATAL",
    )
    return any(k in line for k in keys)

section(f"HOST={HOST} time={datetime.now().isoformat(timespec='seconds')}")

# system / package versions
for p in (
    "/usr/local/share/claude-client/connect-version.txt",
    "/var/log/syslog",
    "/var/log/auth.log",
):
    if os.path.isfile(p):
        a = age(p)
        print(f"FILE {p} age={int(a)}s size={os.path.getsize(p)}" if a is not None else f"FILE {p}")

if os.path.isfile("/usr/local/share/claude-client/connect-version.txt"):
    print("BUNDLE_VERSION=" + open("/usr/local/share/claude-client/connect-version.txt").read().strip())

# common server log roots
candidates = []
for ent in pwd.getpwall():
    if ent.pw_uid < 1000:
        continue
    home = ent.pw_dir
    if not os.path.isdir(home):
        continue
    for pat in (
        f"{home}/.claude/logs/*",
        f"{home}/.claude/*.log",
        f"{home}/.cache/claude*/*",
        f"{home}/.local/state/claude*/*",
    ):
        for p in glob.glob(pat):
            if os.path.isfile(p):
                candidates.append((ent.pw_name, p))

# also global
for pat in (
    "/var/log/claude*",
    "/usr/local/lib/claude-server/logs/*",
    "/tmp/claude*.log",
    "/var/tmp/claude*.log",
):
    for p in glob.glob(pat):
        if os.path.isfile(p):
            candidates.append(("root", p))

# dedupe + sort by mtime desc
seen=set(); files=[]
for u,p in candidates:
    if p in seen: continue
    seen.add(p)
    try:
        files.append((os.path.getmtime(p), u, p, os.path.getsize(p)))
    except OSError:
        pass
files.sort(reverse=True)

section(f"LOG INDEX (newest first, n={len(files)})")
for mt,u,p,sz in files[:60]:
    print(f"{datetime.fromtimestamp(mt).isoformat(timespec='seconds')}  user={u:10}  size={sz:8}  {p}")

# Focus: connect logs + heal + mount related, last 24h preferred else newest 25
cutoff = NOW - 86400
focus = [x for x in files if x[0] >= cutoff]
if len(focus) < 10:
    focus = files[:25]
else:
    focus = focus[:40]

section(f"TAIL FOCUS ({len(focus)} files)")
errors = []
warns = []
version_hits = []
for mt,u,p,sz in focus:
    lines, realsz = tail_file(p, n=60)
    print(f"\n----- {u} :: {p} (mtime={datetime.fromtimestamp(mt).isoformat(timespec='seconds')} size={realsz}) -----")
    # print last 25 always, plus highlight interesting earlier in the 60
    for line in lines[-25:]:
        print(line)
    for line in lines:
        if re.search(r"\b(ERROR|FATAL|Traceback|FAIL)\b", line, re.I):
            errors.append((u,p,line.strip()[:240]))
        elif re.search(r"\bWARN", line, re.I):
            warns.append((u,p,line.strip()[:240]))
        if re.search(r"20260717\.\d+|CONNECT_VERSION|ConnectVersion", line):
            version_hits.append((u,p,line.strip()[:240]))

section("ERROR DIGEST (from tails)")
if not errors:
    print("(none in focused tails)")
else:
    for u,p,line in errors[-40:]:
        print(f"ERR [{u}] {os.path.basename(p)}: {line}")

section("WARN DIGEST")
if not warns:
    print("(none in focused tails)")
else:
    for u,p,line in warns[-30:]:
        print(f"WARN [{u}] {os.path.basename(p)}: {line}")

section("VERSION HITS IN LOGS")
if not version_hits:
    print("(none)")
else:
    for u,p,line in version_hits[-40:]:
        print(f"VER [{u}] {os.path.basename(p)}: {line}")

# journal / syslog snippets if accessible
section("SYSTEM JOURNAL (claude|sshfs|fuse last 200 matching)")
try:
    r = subprocess.run(
        ["journalctl", "-n", "500", "--no-pager"],
        capture_output=True, text=True, timeout=20
    )
    if r.returncode == 0:
        hits = [ln for ln in r.stdout.splitlines() if re.search(r"claude|sshfs|fuse|sshd", ln, re.I)]
        for ln in hits[-80:]:
            print(ln)
        if not hits:
            print("(no matching journal lines)")
    else:
        print("journalctl unavailable/rc=", r.returncode, (r.stderr or "")[:200])
except Exception as e:
    print("journal:", e)

# auth.log last ssh fails
section("AUTH.LOG recent (ssh/sudo) last 40 matching")
for ap in ("/var/log/auth.log", "/var/log/secure"):
    if not os.path.isfile(ap):
        continue
    lines,_ = tail_file(ap, n=400, max_bytes=400_000)
    hits = [ln for ln in lines if re.search(r"sshd|sudo|Failed|Invalid|Accepted", ln)]
    for ln in hits[-40:]:
        print(ln)
    break
else:
    print("(no auth.log)")

print("\nDONE_HOST=" + HOST)
'@

function Run-On($label, $userHost, $useSudo) {
  Write-Host "`n################ $label ($userHost) ################"
  $remotePy = "/tmp/read_logs_$label.py"
  [IO.File]::WriteAllText("$env:TEMP\read_logs_$label.py", $py)
  scp -o BatchMode=yes -q "$env:TEMP\read_logs_$label.py" "${userHost}:$remotePy"
  if ($useSudo) {
    $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
    $wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 ' + $remotePy + $nl
    [IO.File]::WriteAllText("$env:TEMP\rl_$label.sh", $wrap)
    scp -o BatchMode=yes -q "$env:TEMP\rl_$label.sh" "${userHost}:/tmp/rl_$label.sh"
    $out = "$env:TEMP\logs_$label.txt"
    $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15',$userHost,"bash /tmp/rl_$label.sh") -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    if (-not $p.WaitForExit(180000)) { try{$p.Kill()}catch{}; Write-Host "TIMEOUT $label"; return }
    Get-Content $out -Raw
    if (Test-Path "$out.err") { $e = Get-Content "$out.err" -Raw; if ($e) { Write-Host "STDERR: $e" } }
  } else {
    # Smart: try sudo without password first; else run as smart for home logs + sudo -n
    $out = "$env:TEMP\logs_$label.txt"
    $cmd = "sudo -n python3 $remotePy 2>/dev/null || python3 $remotePy"
    $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15',$userHost,$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    if (-not $p.WaitForExit(180000)) { try{$p.Kill()}catch{}; Write-Host "TIMEOUT $label"; return }
    Get-Content $out -Raw
    if (Test-Path "$out.err") { $e = Get-Content "$out.err" -Raw; if ($e) { Write-Host "STDERR: $e" } }
  }
}

Run-On 'SEPIDZ' 'sepidz@192.168.250.70' $true
Run-On 'SMART' 'smart@192.168.210.240' $false
Write-Host '`n======== BOTH DONE ========'
