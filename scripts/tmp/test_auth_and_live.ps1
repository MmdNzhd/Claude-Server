$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$nl = [char]10
$fail = 0
function OK($m){ Write-Host "OK  $m" }
function FAIL($m){ Write-Host "FAIL $m"; $script:fail++ }
function WARN($m){ Write-Host "WARN $m" }

$py = @'
#!/usr/bin/env python3
"""Live auth-probe + tunnel/mount smoke test. Never prints secrets."""
import json, os, pwd, socket, subprocess, time
from collections import Counter

HOST = os.uname().nodename
bv = "?"
p = "/usr/local/share/claude-client/connect-version.txt"
if os.path.isfile(p):
    bv = open(p).read().strip()
print(f"HOST={HOST}")
print(f"BUNDLE={bv}")

# 1) locate probe binary
probe = None
for c in ("/usr/local/bin/claude-auth-probe", "/usr/local/lib/claude-server/claude-auth-probe"):
    if os.path.isfile(c):
        probe = c
        break
print(f"PROBE_BIN={probe or 'MISSING'}")

def run(cmd, t=60):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t)

# 2) run probe once (capture JSON-ish without token fields)
if probe:
    r = run(f"{probe} once 2>&1 || {probe} 2>&1 || {probe} cron 2>&1", t=90)
    out = (r.stdout or "") + (r.stderr or "")
    # redact token-looking strings
    import re
    out = re.sub(r"sk-ant-[A-Za-z0-9_-]+", "sk-ant-REDACTED", out)
    out = re.sub(r'"prefix"\s*:\s*"[^"]+"', '"prefix":"REDACTED"', out)
    out = re.sub(r'"sha256"\s*:\s*"[^"]+"', '"sha256":"REDACTED"', out)
    print("PROBE_RC=", r.returncode)
    # print compact summary lines
    for ln in out.splitlines()[-30:]:
        if len(ln) > 300:
            ln = ln[:300] + "…"
        print("PROBE_OUT:", ln)
else:
    print("PROBE_RC= -1")

# 3) parse recent auth log events (last 50 lines)
auth = "/var/log/claude-auth.log"
ev = Counter(); codes = Counter(); last = None
if os.path.isfile(auth):
    with open(auth, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 200_000))
        lines = f.read().decode("utf-8", "replace").splitlines()[-50:]
    for ln in lines:
        try:
            j = json.loads(ln)
        except Exception:
            continue
        ev[j.get("event", "?")] += 1
        if j.get("http_status") is not None:
            codes[str(j.get("http_status"))] += 1
        last = {k: j.get(k) for k in ("timestamp", "event", "ok", "http_status", "error", "source") if k in j}
    print("AUTH_TAIL_EVENTS", dict(ev))
    print("AUTH_TAIL_HTTP", dict(codes))
    print("AUTH_LAST", last)
else:
    print("AUTH_LOG=missing")

# 4) live users tunnels + mounts
print("LIVE_USERS")
up_n = 0
for ent in sorted(pwd.getpwall(), key=lambda e: e.pw_name):
    if ent.pw_uid < 1000:
        continue
    conf = f"{ent.pw_dir}/.claude-connect.conf"
    if not os.path.isfile(conf):
        continue
    d = {}
    for line in open(conf, encoding="utf-8", errors="replace"):
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            d[k.strip()] = v.strip().strip('"')
    port = d.get("TUNNEL_PORT") or d.get("PORT") or ""
    up = False
    if port.isdigit():
        try:
            s = socket.create_connection(("127.0.0.1", int(port)), 0.8)
            s.close()
            up = True
            up_n += 1
        except OSError:
            up = False
    # mounts for this user from /proc
    mounts = []
    home_m = f"{ent.pw_dir}/mounts/"
    for ln in open("/proc/mounts"):
        parts = ln.split()
        if len(parts) >= 3 and parts[1].startswith(home_m) and "sshfs" in parts[2]:
            mounts.append(parts[1].replace(home_m, ""))
    # heal smoke
    heal = "/usr/local/bin/claude-self-heal"
    hrc = -1
    if os.path.isfile(heal):
        hr = run(f"sudo -u {ent.pw_name} -H {heal} --quiet 2>&1", t=60)
        hrc = hr.returncode
    print(f"  {ent.pw_name}: port={port} {'UP' if up else 'DOWN'} active={d.get('ACTIVE_MOUNT','-')} os={d.get('LAPTOP_OS','?')} mode={d.get('GIT_MODE','?')} mounts={mounts or '-'} heal_rc={hrc}")

print(f"UP_COUNT={up_n}")

# 5) critical bins markers
print("BINS")
for b in ("claude-self-heal", "claude-mount", "laptop-exec", "laptop-exec-setup", "claude-automount"):
    path = f"/usr/local/bin/{b}"
    if not os.path.isfile(path):
        print(f"  MISSING {b}")
        continue
    t = open(path, encoding="utf-8", errors="replace").read()
    cr = open(path, "rb").read().count(b"\r")
    flags = []
    if "_heal_missing_user_bins" in t: flags.append("missing_bins")
    if "_in_proc_mounts" in t or "Prefer /proc/mounts" in t or "Never use mountpoint" in t: flags.append("proc_mounts")
    if "Keep setup itself in PATH" in t: flags.append("setup_self")
    print(f"  {b}: CR={cr} flags={flags or '-'}")

# verdict for auth
auth_ok = False
if last and last.get("ok") is True:
    auth_ok = True
elif last and last.get("http_status") == 200:
    auth_ok = True
print(f"AUTH_PROBE_OK={auth_ok}")
print("DONE")
'@

function Invoke-Test([string]$label, [string]$target, [bool]$useSudo) {
  Write-Host "`n======== $label ========"
  [IO.File]::WriteAllText("$env:TEMP\tal_$label.py", $py)
  scp -o BatchMode=yes -q "$env:TEMP\tal_$label.py" "${target}:/tmp/tal.py"
  $out = "$env:TEMP\tal_$label.txt"
  if ($useSudo) {
    $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
    $wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/tal.py' + $nl
    [IO.File]::WriteAllText("$env:TEMP\tal_$label.sh", $wrap)
    scp -o BatchMode=yes -q "$env:TEMP\tal_$label.sh" "${target}:/tmp/tal.sh"
    $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15',$target,'bash /tmp/tal.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  } else {
    $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15',$target,'sudo -n python3 /tmp/tal.py 2>/dev/null || python3 /tmp/tal.py') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  }
  if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch {}; FAIL "$label TIMEOUT"; return $null }
  $txt = Get-Content $out -Raw
  Write-Host $txt
  return $txt
}

$sepidz = Invoke-Test 'SEPIDZ' 'sepidz@192.168.250.70' $true
$smart  = Invoke-Test 'SMART'  'smart@192.168.210.240' $false

Write-Host "`n======== VERDICT ========"
foreach ($pair in @(@('SEPIDZ',$sepidz), @('SMART',$smart))) {
  $name = $pair[0]; $t = $pair[1]
  if (-not $t) { FAIL "$name no output"; continue }
  if ($t -match 'BUNDLE=([^\r\n]+)') { OK "$name bundle=$($Matches[1])" } else { WARN "$name no bundle" }
  if ($t -match 'AUTH_PROBE_OK=True') { OK "$name auth probe OK" } else { FAIL "$name auth probe NOT OK (401/token)" }
  if ($t -match 'UP_COUNT=(\d+)') {
    $n = [int]$Matches[1]
    if ($n -ge 1) { OK "$name tunnels_up=$n" } else { WARN "$name no tunnels up" }
  }
  if ($t -match 'claude-self-heal: CR=0') { OK "$name heal bin OK" } else { WARN "$name heal bin check" }
  if ($t -match 'heal_rc=0') { OK "$name heal runs for users" } else { WARN "$name some heal rc non-zero?" }
}

Write-Host "local_fail=$fail"
if ($fail -ne 0) { Write-Host 'TEST_RED'; exit 1 }
Write-Host 'TEST_GREEN_INFRA'
# auth may still be red - exit 2 to distinguish
if (($sepidz + $smart) -match 'AUTH_PROBE_OK=False') {
  Write-Host 'TEST_AUTH_RED'
  exit 2
}
Write-Host 'TEST_ALL_GREEN'
exit 0
