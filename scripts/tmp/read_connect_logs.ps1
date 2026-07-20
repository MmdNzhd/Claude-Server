$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$nl = [char]10

$py = @'
#!/usr/bin/env python3
import os, pwd, glob, re, json, socket
from collections import Counter
from datetime import datetime

HOST = os.uname().nodename
bv = "?"
if os.path.isfile("/usr/local/share/claude-client/connect-version.txt"):
    bv = open("/usr/local/share/claude-client/connect-version.txt").read().strip()
print(f"HOST={HOST} bundle={bv}")

paths=[]
for ent in pwd.getpwall():
    if ent.pw_uid < 1000: continue
    home=ent.pw_dir
    for pat in [
        f"{home}/.claude/logs/**",
        f"{home}/.claude/logs/*",
        f"{home}/.claude/**/*.log",
        f"{home}/.config/claude-connect/**",
        f"{home}/.cache/claude-connect/**",
    ]:
        for p in glob.glob(pat, recursive=True):
            if os.path.isfile(p) and ("connect" in p.lower() or p.endswith(".log")):
                paths.append((ent.pw_name,p))
for p in glob.glob("/var/log/claude*"):
    if os.path.isfile(p):
        paths.append(("root",p))

seen=set(); files=[]
for u,p in paths:
    if p in seen: continue
    seen.add(p)
    try: files.append((os.path.getmtime(p), u, p, os.path.getsize(p)))
    except: pass
files.sort(reverse=True)
print(f"FOUND_LOGS={len(files)}")
for mt,u,p,sz in files[:50]:
    print(f"  {datetime.fromtimestamp(mt).isoformat(timespec='seconds')} {u:10} {sz:9} {p}")

ver_re = re.compile(r"20260717\.(\d+)")

def tail_lines(path, n=300, maxb=600000):
    with open(path,"rb") as f:
        f.seek(0,2); sz=f.tell(); f.seek(max(0,sz-maxb))
        return f.read().decode("utf-8","replace").splitlines()[-n:]

print("\n=== CONNECT LOG ANALYSIS ===")
ver_counts=Counter(); err_samples=[]; warn_samples=[]
connect_files=[x for x in files if "connect" in x[2].lower()]
if not connect_files:
    connect_files=files[:10]

for mt,u,p,sz in connect_files[:30]:
    try:
        lines=tail_lines(p)
    except Exception as e:
        print(f"skip {p}: {e}"); continue
    print(f"\n--- {u} {p} (tail {len(lines)}) ---")
    for ln in lines[-25:]:
        if len(ln)>220: ln=ln[:220]+"…"
        print(ln)
    for ln in lines:
        for m in ver_re.finditer(ln):
            ver_counts[m.group(0)] += 1
        if re.search(r"\b(ERROR|FAIL|FATAL)\b", ln, re.I) and "PROBE_FAIL" not in ln:
            err_samples.append((u, os.path.basename(p), ln.strip()[:200]))
        if re.search(r"\bWARN", ln, re.I):
            warn_samples.append((u, os.path.basename(p), ln.strip()[:200]))

print("\n=== VERSION COUNTS IN CONNECT LOGS ===")
for v,c in ver_counts.most_common(20):
    print(f"  {v}: {c}")
if not ver_counts:
    print("  (none)")

print("\n=== NON-AUTH ERRORS ===")
for u,b,ln in err_samples[-30:]:
    print(f"ERR [{u}/{b}] {ln}")
if not err_samples: print("(none)")

print("\n=== WARNS ===")
for u,b,ln in warn_samples[-25:]:
    print(f"WARN [{u}/{b}] {ln}")
if not warn_samples: print("(none)")

print("\n=== AUTH PROBE SUMMARY ===")
auth="/var/log/claude-auth.log"
if os.path.isfile(auth):
    lines=tail_lines(auth, n=800, maxb=900000)
    ev=Counter(); codes=Counter(); last=None
    for ln in lines:
        try: j=json.loads(ln)
        except Exception: continue
        ev[j.get("event","?")] += 1
        if j.get("http_status") is not None:
            codes[str(j.get("http_status"))] += 1
        last=j
    print("events", dict(ev))
    print("http_status", dict(codes))
    if last:
        print("last_event", last.get("event"), "http", last.get("http_status"), "ts", last.get("timestamp"), "source", last.get("source"))
else:
    print("no auth log")

print("\n=== LIVE USER CONFS ===")
for ent in sorted(pwd.getpwall(), key=lambda e:e.pw_name):
    if ent.pw_uid < 1000: continue
    conf=f"{ent.pw_dir}/.claude-connect.conf"
    if not os.path.isfile(conf): continue
    d={}
    for line in open(conf, encoding="utf-8", errors="replace"):
        if "=" in line and not line.strip().startswith("#"):
            k,v=line.split("=",1); d[k.strip()]=v.strip().strip('"')
    port=d.get("TUNNEL_PORT") or d.get("PORT") or ""
    up="?"
    if port.isdigit():
        try:
            s=socket.create_connection(("127.0.0.1", int(port)), 0.8); s.close(); up="UP"
        except OSError:
            up="DOWN"
    print(f"  {ent.pw_name}: mode={d.get('GIT_MODE','?')} os={d.get('LAPTOP_OS','?')} port={port} {up} active={d.get('ACTIVE_MOUNT','-')}")

print("DONE="+HOST)
'@

function Invoke-LogRead([string]$label, [string]$target, [bool]$useSudo) {
  Write-Host "`n#### $label ####"
  [IO.File]::WriteAllText("$env:TEMP\rcl_$label.py", $py)
  scp -o BatchMode=yes -q "$env:TEMP\rcl_$label.py" "${target}:/tmp/rcl.py"
  $out = "$env:TEMP\rcl_$label.txt"
  if ($useSudo) {
    $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
    $wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/rcl.py' + $nl
    [IO.File]::WriteAllText("$env:TEMP\rcl_$label.sh", $wrap)
    scp -o BatchMode=yes -q "$env:TEMP\rcl_$label.sh" "${target}:/tmp/rcl.sh"
    $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15',$target,'bash /tmp/rcl.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  } else {
    $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15',$target,'sudo -n python3 /tmp/rcl.py 2>/dev/null || python3 /tmp/rcl.py') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  }
  [void]$p.WaitForExit(120000)
  Get-Content $out -Raw
}

Invoke-LogRead 'SEPIDZ' 'sepidz@192.168.250.70' $true
Invoke-LogRead 'SMART' 'smart@192.168.210.240' $false
