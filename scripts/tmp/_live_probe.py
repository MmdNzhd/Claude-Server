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
