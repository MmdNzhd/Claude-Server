$ErrorActionPreference='Continue'
Write-Host '==== SMART laptop-exec CRLF ===='
& ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.210.240 @'
python3 - <<'PY'
import os
paths=["/usr/local/bin/laptop-exec","/usr/local/lib/claude-mount"]
for home in sorted(os.listdir("/home")):
    p=f"/home/{home}/.local/bin/laptop-exec"
    if os.path.exists(p): paths.append(os.path.realpath(p))
seen=set()
for p in paths:
    if p in seen or not os.path.isfile(p): continue
    seen.add(p)
    raw=open(p,"rb").read()
    print(("CRLF" if b"\r" in raw else "LF  "), p, "bytes", len(raw))
PY
'@
