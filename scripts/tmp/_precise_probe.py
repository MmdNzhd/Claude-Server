import paramiko, re
c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.210.240", username="smart", timeout=15, allow_agent=True, look_for_keys=True)
cmd=r'''
python3 - <<'PY'
import subprocess, concurrent.futures, time
PORT=21003
def new():
    p=subprocess.run(["bash","-lc",f"timeout 3 nc -w 2 127.0.0.1 {PORT} 2>/dev/null | head -1"],capture_output=True,text=True,timeout=5)
    return (p.stdout or "").strip()
def old():
    p=subprocess.run(["bash","-lc",f"timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{PORT} 2>/dev/null && timeout 2 nc 127.0.0.1 {PORT} 2>/dev/null | head -1'"],capture_output=True,text=True,timeout=6)
    return (p.stdout or "").strip()
def classify(b):
    if b.startswith("SSH-2.0-") and "OpenSSH_for_Windows" in b: return "ok"
    if "MaxStartups" in b: return "max"
    if not b: return "empty"
    return "other:"+b[:40]
# 3 rounds parallel 12
for name,fn in [("NEW",new),("OLD",old)]:
    totals={"ok":0,"max":0,"empty":0,"other":0}
    for round in range(1,4):
        with concurrent.futures.ThreadPoolExecutor(12) as ex:
            res=list(ex.map(lambda _: fn(), range(12)))
        counts={"ok":0,"max":0,"empty":0,"other":0}
        for b in res:
            k=classify(b)
            if k.startswith("other"): counts["other"]+=1
            else: counts[k]+=1
        for k in totals: totals[k]+=counts[k]
        print(f"{name}_R{round} ok={counts['ok']} max={counts['max']} empty={counts['empty']} other={counts['other']}")
        time.sleep(0.5)
    print(f"{name}_TOTAL ok={totals['ok']}/36 max={totals['max']} empty={totals['empty']}")
PY
'''
_,o,e=c.exec_command(cmd, timeout=120)
print(o.read().decode())
c.close()
