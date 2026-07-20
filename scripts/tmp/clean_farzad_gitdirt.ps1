$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
$py = @'
import subprocess
def su(user, cmd):
    return subprocess.run(["su","-",user,"-c",cmd], text=True, capture_output=True, timeout=90)
for proj in ("frontend","backend"):
    cmds = [
      f"laptop-exec git -p {proj} -- checkout -- .vscode/settings.json",
      f"laptop-exec run -p {proj} -- cmd /c \"del /q .deep-e2e.txt .claude-e2e-probe-3732810 2>nul\"",
      f"laptop-exec git -p {proj} -- status -sb",
    ]
    print(f"=== {proj}", flush=True)
    for c in cmds:
      r = su("farzadb", c)
      out = ((r.stdout or "")+(r.stderr or "")).strip()
      if out: print(out[:400], flush=True)
print("CLEAN_DONE", flush=True)
'@
[IO.File]::WriteAllText("$env:TEMP\cfd.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\cfd.py" 'sepidz@192.168.250.70:/tmp/cfd.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/cfd.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\cfd.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\cfd.sh" 'sepidz@192.168.250.70:/tmp/cfd.sh'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/cfd.sh') -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\cfd_out.txt" -RedirectStandardError "$env:TEMP\cfd_err.txt"
if (-not $p.WaitForExit(120000)) { try{$p.Kill()}catch{}; exit 1 }
Get-Content "$env:TEMP\cfd_out.txt" | Write-Host
exit $p.ExitCode
