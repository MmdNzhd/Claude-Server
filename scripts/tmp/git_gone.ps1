$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$shim = Join-Path $root 'scripts\server\git-via-laptop-exec.sh'
if (Test-Path $shim) {
  Remove-Item -Force $shim
  Write-Host "removed repo shim"
}
$mount = Get-Content (Join-Path $root 'scripts\server\claude-mount.sh') -Raw
if ($mount -notmatch '"git.enabled": False') { throw 'mount policy missing git.enabled False' }
Write-Host 'repo policy OK (git disabled)'

. "$root\publish\Get-DeployCredentials.ps1"
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q "$root\scripts\tmp\kill_cursor_git.py" 'sepidz@192.168.250.70:/tmp/kill_cursor_git.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/kill_cursor_git.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\kg.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\kg.sh" 'sepidz@192.168.250.70:/tmp/kg.sh'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/kg.sh') -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\kg_out.txt" -RedirectStandardError "$env:TEMP\kg_err.txt"
if (-not $p.WaitForExit(60000)) { try{$p.Kill()}catch{}; throw 'timeout' }
Get-Content "$env:TEMP\kg_out.txt" | Write-Host
Get-Content "$env:TEMP\kg_err.txt" -ErrorAction SilentlyContinue | Write-Host
if ($p.ExitCode -ne 0) { exit $p.ExitCode }

# clean farzadb dirty vscode + probes via laptop-exec as user
$clean = @'
import subprocess
def su(user, cmd):
    return subprocess.run(["su","-",user,"-c",cmd], text=True, capture_output=True, timeout=90)
for proj in ("frontend","backend"):
    r = su("farzadb", f"laptop-exec git -p {proj} -- checkout -- .vscode/settings.json 2>/dev/null; laptop-exec run -p {proj} -- cmd /c del .deep-e2e.txt .claude-e2e-probe-3732810 2>nul; laptop-exec git -p {proj} -- status -sb")
    print(proj, (r.stdout or "")+(r.stderr or ""))
'@
[IO.File]::WriteAllText("$env:TEMP\clean_f.py", $clean)
scp -o BatchMode=yes -q "$env:TEMP\clean_f.py" 'sepidz@192.168.250.70:/tmp/clean_f.py'
$wrap2 = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/clean_f.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\cf.sh", $wrap2)
scp -o BatchMode=yes -q "$env:TEMP\cf.sh" 'sepidz@192.168.250.70:/tmp/cf.sh'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/cf.sh') -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\cf_out.txt" -RedirectStandardError "$env:TEMP\cf_err.txt"
if (-not $p.WaitForExit(120000)) { try{$p.Kill()}catch{}; throw 'clean timeout' }
Get-Content "$env:TEMP\cf_out.txt" | Write-Host
Write-Host 'GIT_GONE_DONE'
