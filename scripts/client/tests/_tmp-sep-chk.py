#!/usr/bin/env python3
import subprocess, time, threading, tempfile
from pathlib import Path
PW="sepidz@Admin"; T="sepidz@192.168.250.70"
OPTS=["-o","BatchMode=yes","-o","ConnectTimeout=12","-o","ControlMaster=no","-o","ControlPath=none"]

def one(body, timeout=25):
    local=Path(tempfile.gettempdir())/"sc.sh"
    local.write_text("#!/bin/bash\nset +e\n"+body+"\necho __DONE__\n",encoding="utf-8",newline="\n")
    subprocess.run(["scp"]+OPTS+["-q",str(local),f"{T}:/tmp/sc.sh"],check=True,timeout=12)
    p=subprocess.Popen(["ssh","-n"]+OPTS+[T,f"printf '%s\\n' '{PW}' | sudo -S -p '' bash /tmp/sc.sh"],
                       stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,bufsize=1)
    out=[]
    def r():
        for line in iter(p.stdout.readline,""):
            out.append(line); print(line,end="",flush=True)
            if "__DONE__" in line: break
    th=threading.Thread(target=r,daemon=True); th.start()
    end=time.time()+timeout
    while time.time()<end:
        if any("__DONE__" in x for x in out):
            time.sleep(0.2); p.kill(); break
        if p.poll() is not None: break
        time.sleep(0.05)
    else:
        p.kill(); print("(t/o)",flush=True)
    th.join(1)

# Install only (no user loop)
one(r'''
ST=/tmp/le-sep-unpack
rm -rf "$ST"; mkdir -p "$ST"
tar -C "$ST" -xzf /tmp/le-sep-deploy.tgz
install -m 755 "$ST/bin/laptop-exec" /usr/local/bin/laptop-exec
install -m 755 "$ST/bin/laptop-exec-setup" /usr/local/bin/laptop-exec-setup
install -m 755 "$ST/hooks/laptop-exec-guard-wrap.sh" /usr/local/bin/laptop-exec-guard-wrap.sh
install -m 755 "$ST/hooks/laptop-exec-guard.sh" /usr/local/bin/laptop-exec-guard.sh
install -m 755 "$ST/hooks/laptop-exec-session.sh" /usr/local/bin/laptop-exec-session.sh
install -m 755 "$ST/hooks/laptop-exec-shell-scan.py" /usr/local/bin/laptop-exec-shell-scan.py
mkdir -p /usr/local/lib/claude-server/cursor-hooks
cp -a "$ST/hooks/." /usr/local/lib/claude-server/cursor-hooks/
test -x /usr/local/bin/laptop-exec-guard-wrap.sh && echo WRAP_BIN_OK || echo WRAP_BIN_MISS
test -x /usr/local/bin/laptop-exec && echo LE_OK
echo HM=$(stat -c%s /home/hosseinm/.claude/logs/connect-20260721.log 2>/dev/null || echo na)
''')

# One user setup at a time
for u in ["alit","farzadb","hosseinm","nimaz"]:
    one(f'''
sudo -u {u} env HOME=/home/{u} laptop-exec-setup >/tmp/les.txt 2>&1
hj=/home/{u}/.cursor/hooks.json
if [ -f "$hj" ] && grep -q laptop-exec-guard-wrap "$hj"; then echo {u} WRAP_OK; else echo {u} WRAP_BAD; tail -3 /tmp/les.txt; fi
''')
