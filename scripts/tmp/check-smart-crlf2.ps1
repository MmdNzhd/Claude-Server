$py = @'
import os
paths=["/usr/local/bin/laptop-exec","/usr/local/lib/claude-mount"]
for home in sorted(os.listdir("/home")):
    p=f"/home/{home}/.local/bin/laptop-exec"
    if os.path.exists(p):
        paths.append(os.path.realpath(p))
seen=set(); bad=0
for p in paths:
    if p in seen or not os.path.isfile(p):
        continue
    seen.add(p)
    raw=open(p,"rb").read()
    flag="CRLF" if b"\r" in raw else "LF"
    if flag=="CRLF":
        bad += 1
        open(p,"wb").write(raw.replace(b"\r\n",b"\n").replace(b"\r",b"\n"))
        print("FIXED", p)
    else:
        print(flag, p)
print("BAD_COUNT_BEFORE_FIX", bad)
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
& ssh -o BatchMode=yes -o ConnectTimeout=20 smart@192.168.210.240 "echo $b64 | base64 -d | sudo -n python3 -"
Write-Host "smart_exit=$LASTEXITCODE"
