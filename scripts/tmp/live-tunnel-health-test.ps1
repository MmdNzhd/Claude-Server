$ErrorActionPreference='Continue'
$Expected='20260717.5'
$fail=0
function Pass($m){ Write-Host "PASS  $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL  $m" -ForegroundColor Red; $script:fail++ }

Write-Host '======== A) Running connect session version ========' -ForegroundColor Cyan
# Find connect.log being written (active session)
$logs = @(
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log',
  (Join-Path $PSScriptRoot '..\..\scripts\client\windows\connect.log'),
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.log'
) | Where-Object { Test-Path $_ }
# Also search recent connect.log near Desktop/publish and common places
$extra = Get-ChildItem -Path 'C:\Users\Smart\Desktop\claude-publish' -Recurse -Filter 'connect.log' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 3
foreach($e in $extra){ if($logs -notcontains $e.FullName){ $logs += $e.FullName } }

if(-not $logs){ Write-Host 'WARN  no connect.log found (session may use other path)' -ForegroundColor Yellow }
foreach($log in $logs){
  $item=Get-Item $log
  Write-Host ("LOG  {0}  mtime={1}  size={2}" -f $log, $item.LastWriteTime, $item.Length)
  $tail = Get-Content $log -Tail 80
  $ver = ($tail | Select-String -Pattern 'version=2026\d+' | Select-Object -Last 1)
  $verLine = if($ver){ $ver.Line } else { '' }
  Write-Host "  last_version_line=$verLine"
  $drops = @(Select-String -Path $log -Pattern 'connection dropped|TUNNEL_DROP|banner_miss_tcp_open|TUNNEL_BANNER soft_fail|reason=maxstartups|nc -w 2' | Select-Object -Last 15)
  Write-Host ("  recent_tunnel_events={0}" -f $drops.Count)
  $drops | ForEach-Object { Write-Host ("    " + $_.Line.Substring(0,[Math]::Min(140,$_.Line.Length))) }
}

# Active ssh -R tunnel?
$tun = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match '-R\s+21003:localhost:22' } | Select-Object -First 1
if($tun){ Pass "local reverse tunnel alive pid=$($tun.ProcessId)" } else { Fail 'local reverse tunnel (-R 21003) not found' }

Write-Host ''
Write-Host '======== B) Server-side probe stress (paramiko) ========' -ForegroundColor Cyan
$py = @'
import concurrent.futures, subprocess, time, re, sys
from pathlib import Path
import paramiko

ROOT=Path(r"D:\Smart\Claude-Code-Server")

def connect():
    c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect("192.168.210.240", username="smart", timeout=15, allow_agent=True, look_for_keys=True)
    return c

def run(c, cmd, timeout=60):
    _,o,e=c.exec_command(cmd, timeout=timeout)
    out=o.read().decode("utf-8","replace")
    err=e.read().decode("utf-8","replace")
    code=o.channel.recv_exit_status()
    return code, out, err

script = r'''
python3 - <<'PY'
import socket, concurrent.futures, time, subprocess, os

PORT=21003

def banner_nc():
    p=subprocess.run(["bash","-lc", f"timeout 3 nc -w 2 127.0.0.1 {PORT} 2>/dev/null | head -1"], capture_output=True, text=True, timeout=5)
    return (p.stdout or "").strip()

def banner_double():
    # OLD buggy probe
    p=subprocess.run(["bash","-lc", f"timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{PORT} 2>/dev/null && timeout 2 nc 127.0.0.1 {PORT} 2>/dev/null | head -1' 2>/dev/null"], capture_output=True, text=True, timeout=6)
    return (p.stdout or "").strip()

def ok(b):
    return b.startswith("SSH-2.0-") and "OpenSSH_for_Windows" in b

print("=== sequential NEW nc-only x10 ===")
n_ok=0
for i in range(10):
    b=banner_nc(); n_ok += 1 if ok(b) else 0
    print(f"NEW_SEQ {i+1} [{b[:60]}]")
print(f"NEW_SEQ_OK {n_ok}/10")

print("=== parallel NEW x12 ===")
with concurrent.futures.ThreadPoolExecutor(12) as ex:
    res=list(ex.map(lambda _: banner_nc(), range(12)))
n_ok=sum(1 for b in res if ok(b))
n_ms=sum(1 for b in res if "MaxStartups" in b)
n_empty=sum(1 for b in res if not b)
print(f"NEW_PAR_OK {n_ok}/12 maxstartups={n_ms} empty={n_empty}")
for i,b in enumerate(res,1):
    print(f"NEW_PAR {i} [{b[:60]}]")

print("=== parallel OLD double x12 ===")
with concurrent.futures.ThreadPoolExecutor(12) as ex:
    res=list(ex.map(lambda _: banner_double(), range(12)))
n_ok=sum(1 for b in res if ok(b))
n_ms=sum(1 for b in res if "MaxStartups" in b)
n_empty=sum(1 for b in res if not b)
print(f"OLD_PAR_OK {n_ok}/12 maxstartups={n_ms} empty={n_empty}")

print("=== soft-fail simulation: 3 retries like Sync ===")
def probe_with_retries():
    for i in range(3):
        b=banner_nc()
        if ok(b):
            return True, b, i+1
        time.sleep(0.3)
    # tcp open?
    try:
        s=socket.create_connection(("127.0.0.1", PORT), 2); s.close(); tcp=True
    except Exception:
        tcp=False
    return False, f"tcp={tcp}", 3

# Hold 10 unauth connections (near MaxStartups), then retry probe
holders=[]
for _ in range(10):
    try:
        s=socket.create_connection(("127.0.0.1",PORT),2)
        holders.append(s)
    except Exception as e:
        holders.append(e)
print(f"HELD {sum(1 for h in holders if isinstance(h, socket.socket))}")
ok1, detail, attempts = probe_with_retries()
print(f"UNDER_HOLD retries_ok={ok1} detail={detail} attempts={attempts}")
# After release
for h in holders:
    if isinstance(h, socket.socket):
        try: h.close()
        except: pass
time.sleep(0.4)
ok2, detail2, attempts2 = probe_with_retries()
print(f"AFTER_RELEASE retries_ok={ok2} detail={detail2} attempts={attempts2}")

# Real SSH still works under mild load
p=subprocess.run(["bash","-lc", f"timeout 8 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $HOME/.ssh/claude_laptop -p {PORT} Smart@127.0.0.1 echo SSH_OK 2>/dev/null | tail -1"], capture_output=True, text=True, timeout=12)
print(f"SSH_OK_LINE [{(p.stdout or '').strip()}]")
PY
'''

c=connect()
code,out,err=run(c, script, timeout=120)
print(out)
if err.strip():
    print("STDERR", err[-400:])
print(f"REMOTE_EXIT {code}")
c.close()
'@
Set-Content -Path 'scripts\tmp\_live_probe.py' -Value $py -Encoding UTF8
$remoteOut = & python -X utf8 'scripts\tmp\_live_probe.py' 2>&1
$remoteOut | ForEach-Object { "$_" }

# Score remote results
$text = ($remoteOut | Out-String)
if($text -match 'NEW_SEQ_OK 10/10'){ Pass 'NEW sequential 10/10' } else { Fail "NEW sequential: $(($text | Select-String 'NEW_SEQ_OK').Line)" }
if($text -match 'NEW_PAR_OK (\d+)/12'){
  $n=[int]$matches[1]
  if($n -ge 10){ Pass "NEW parallel $n/12 (tolerant)" } else { Fail "NEW parallel only $n/12" }
} else { Fail 'NEW parallel missing' }
if($text -match 'OLD_PAR_OK (\d+)/12'){
  $n=[int]$matches[1]
  Write-Host ("INFO  OLD parallel $n/12 (baseline; often worse under MaxStartups)") -ForegroundColor DarkGray
}
if($text -match 'AFTER_RELEASE retries_ok=True'){ Pass 'retries recover after MaxStartups pressure' } else { Fail 'retries after release failed' }
if($text -match 'SSH_OK_LINE \[SSH_OK\]'){ Pass 'reverse SSH still works after stress' } else { Fail 'reverse SSH failed after stress' }

Write-Host ''
Write-Host '======== C) Dot-source git-mode helpers smoke (syntax+functions) ========' -ForegroundColor Cyan
$smoke = @'
$ErrorActionPreference='Stop'
# Minimal stubs required by git-mode.ps1
function Write-ConnectLog { param($Message,$Level='INFO') }
function SshX { param([Parameter(ValueFromRemainingArguments=$true)]$Args) }
$Port = 21003
$script:ConnectLogPath = $null
. 'scripts\client\git-mode.ps1'
if(-not (Get-Command Get-TunnelBanner -EA SilentlyContinue)){ throw 'Get-TunnelBanner missing' }
if(-not (Get-Command Test-TunnelUp -EA SilentlyContinue)){ throw 'Test-TunnelUp missing' }
if(-not (Get-Command Sync-SessionTunnelProcess -EA SilentlyContinue)){ throw 'Sync missing' }
# Positive-cache only: empty must not poison
$script:TunnelBannerCacheAt = Get-Date
$script:TunnelBannerCacheBanner = ''
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheInvalidate = $false
# Monkeypatch Get-TunnelBanner internals by overriding SshX to return good banner once
function SshX {
  param([Parameter(ValueFromRemainingArguments=$true)]$a)
  $cmd = ($a -join ' ')
  if($cmd -match 'nc -w 2'){ return 'SSH-2.0-OpenSSH_for_Windows_9.5' }
  if($cmd -match 'echo open'){ return 'open' }
  return ''
}
Clear-TunnelBannerCache
$b = Get-TunnelBanner
if($b -notmatch 'OpenSSH_for_Windows'){ throw "banner=$b" }
if(-not (Test-TunnelUp)){ throw 'Test-TunnelUp false after good banner' }
# Simulate miss then soft tcp path pieces
function SshX { param([Parameter(ValueFromRemainingArguments=$true)]$a)
  $cmd=($a -join ' ')
  if($cmd -match 'nc -w 2'){ return '' }
  if($cmd -match 'echo open|Connection refused'){ return 'open' }
  return ''
}
Clear-TunnelBannerCache
$b2 = Get-TunnelBanner
if($b2 -ne ''){ throw "expected empty got $b2" }
if($script:TunnelBannerCacheUp){ throw 'negative cached as up' }
if($script:TunnelBannerCacheAt){ throw 'negative cache timestamp set (poison)' }
Write-Output 'SMOKE_OK'
'@
Set-Content 'scripts\tmp\_smoke_gitmode.ps1' -Value $smoke -Encoding UTF8
$smokeOut = & powershell -NoProfile -ExecutionPolicy Bypass -File 'scripts\tmp\_smoke_gitmode.ps1' 2>&1
$smokeOut | ForEach-Object { "$_" }
if(($smokeOut | Out-String) -match 'SMOKE_OK'){ Pass 'git-mode smoke (cache/poison guards)' } else { Fail "git-mode smoke failed: $smokeOut" }

Write-Host ''
Write-Host '======== D) Client auto-update source on server matches .5 ========' -ForegroundColor Cyan
# What connect-update would pull
$chk = & python -X utf8 -c @"
import paramiko
c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('192.168.210.240', username='smart', timeout=15, allow_agent=True, look_for_keys=True)
_,o,_=c.exec_command('cat /usr/local/share/claude-client/connect-version.txt; grep -n \"nc -w 2\" /usr/local/share/claude-client/git-mode.ps1 | head -1; grep -n tunnelSyncOk /usr/local/share/claude-client/connect.ps1 | head -1')
print(o.read().decode('utf-8','replace'))
c.close()
"@
Write-Host $chk
if(($chk | Out-String) -match '20260717\.5' -and ($chk | Out-String) -match 'nc -w 2' -and ($chk | Out-String) -match 'tunnelSyncOk'){
  Pass 'server auto-update bundle serves .5 fix'
} else { Fail 'server auto-update bundle incomplete' }

Write-Host ''
Write-Host '======== SUMMARY ========' -ForegroundColor Cyan
if($fail -eq 0){ Write-Host 'ALL_TESTS_PASS fail=0' -ForegroundColor Green; exit 0 }
Write-Host "TESTS_HAVE_FAILURES fail=$fail" -ForegroundColor Red; exit 1
