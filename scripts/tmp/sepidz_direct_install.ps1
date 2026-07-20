$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"

$expected = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
$installScript = Join-Path $root 'scripts\server\commands\install-client-bundle.sh'
$remoteDir = '.claude-client-deploy'
$zip = Join-Path $env:TEMP 'claude-client-bundle-sepidz-direct.zip'
if (-not (Test-Path $zip)) { throw "missing $zip" }
Write-Host "expected=$expected"

ssh -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "mkdir -p ~/$remoteDir"
scp -o BatchMode=yes -q $zip "sepidz@192.168.250.70:~/$remoteDir/bundle.zip"
# strip CRLF on install script before upload
$inst = [IO.File]::ReadAllBytes($installScript)
$instTxt = [Text.Encoding]::UTF8.GetString($inst).Replace("`r`n","`n").Replace("`r","`n")
[IO.File]::WriteAllBytes("$env:TEMP\install-client-bundle.sh", [Text.Encoding]::UTF8.GetBytes($instTxt))
scp -o BatchMode=yes -q "$env:TEMP\install-client-bundle.sh" "sepidz@192.168.250.70:~/$remoteDir/install-client-bundle.sh"
Write-Host 'UPLOADED'

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
# LF-only bash wrap
$lines = @(
  '#!/bin/bash',
  'set -e',
  ('PW=$(echo {0} | base64 -d)' -f $pwB64),
  ('RD="$HOME/{0}"' -f $remoteDir),
  'python3 - <<''PY''',
  'from pathlib import Path',
  ('p = Path.home() / "{0}" / "install-client-bundle.sh"' -f $remoteDir),
  'b = p.read_bytes() if p.exists() else b""',
  'if b.startswith(b"\xef\xbb\xbf"): b = b[3:]',
  'p.write_bytes(b.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))',
  'PY',
  'chmod +x "$RD/install-client-bundle.sh"',
  'printf ''%s\n'' "$PW" | sudo -S -p '''' mkdir -p /usr/local/lib/claude-server/commands',
  'printf ''%s\n'' "$PW" | sudo -S -p '''' cp -f "$RD/install-client-bundle.sh" /usr/local/lib/claude-server/commands/install-client-bundle.sh',
  'printf ''%s\n'' "$PW" | sudo -S -p '''' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh',
  'printf ''%s\n'' "$PW" | sudo -S -p '''' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "$RD/bundle.zip"',
  'ec=$?',
  'echo INSTALL_EC=$ec',
  'exit $ec'
)
$wrap = ($lines -join "`n") + "`n"
[IO.File]::WriteAllBytes("$env:TEMP\sep_install.sh", [Text.Encoding]::UTF8.GetBytes($wrap))
scp -o BatchMode=yes -q "$env:TEMP\sep_install.sh" 'sepidz@192.168.250.70:/tmp/sep_install.sh'

$out = "$env:TEMP\sep_install_out.txt"
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ServerAliveInterval=5','-o','ServerAliveCountMax=12','sepidz@192.168.250.70','bash /tmp/sep_install.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(300000)) { try{$p.Kill()}catch{}; throw 'TIMEOUT' }
Write-Host '--- stdout ---'
Get-Content $out -Raw -ErrorAction SilentlyContinue
Write-Host '--- stderr ---'
Get-Content "$out.err" -Raw -ErrorAction SilentlyContinue
Write-Host "ssh_exit=$($p.ExitCode)"

$sepVer = (ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
$smartOut = "$env:TEMP\smartv_fin.txt"
$p2 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','smart@192.168.210.240',"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $smartOut -RedirectStandardError "$smartOut.err"
[void]$p2.WaitForExit(12000)
$smartVer = if (Test-Path $smartOut) { (Get-Content $smartOut -Raw).Trim() } else { '?' }
Write-Host "SEPIDZ_LIVE=$sepVer SMART_LIVE=$smartVer"
if ($sepVer -ne $expected) { throw "mismatch got=$sepVer want=$expected" }

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
foreach ($pair in @(
  @("$root\scripts\server\claude-self-heal.sh","/tmp/claude-self-heal.sh"),
  @("$root\scripts\server\laptop-exec-setup.sh","/tmp/laptop-exec-setup.sh"),
  @("$root\scripts\server\claude-automount.sh","/tmp/claude-automount.sh"),
  @("$root\scripts\server\laptop-exec.sh","/tmp/laptop-exec.sh"),
  @("$root\scripts\server\claude-mount.sh","/tmp/claude-mount.sh")
)) { scp -o BatchMode=yes -q $pair[0] ("sepidz@192.168.250.70:"+$pair[1]) }
$py = "import os`nm={'/tmp/claude-self-heal.sh':['/usr/local/bin/claude-self-heal'],'/tmp/laptop-exec-setup.sh':['/usr/local/bin/laptop-exec-setup'],'/tmp/claude-automount.sh':['/usr/local/bin/claude-automount'],'/tmp/laptop-exec.sh':['/usr/local/bin/laptop-exec','/usr/local/lib/claude-server/laptop-exec.sh'],'/tmp/claude-mount.sh':['/usr/local/bin/claude-mount','/usr/local/lib/claude-mount']}`nfor s,ds in m.items():`n d=open(s,'rb').read().replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n')`n for x in ds:`n  os.makedirs(os.path.dirname(x),exist_ok=True); open(x,'wb').write(d); os.chmod(x,0o755); print('ok',x)`nprint('BINS_DONE')`n"
# write py with LF
[IO.File]::WriteAllBytes("$env:TEMP\bins.py", [Text.Encoding]::UTF8.GetBytes(($py -replace '\\n',"`n")))
# simpler py write
$py2 = @'
import os
m={
"/tmp/claude-self-heal.sh":["/usr/local/bin/claude-self-heal"],
"/tmp/laptop-exec-setup.sh":["/usr/local/bin/laptop-exec-setup"],
"/tmp/claude-automount.sh":["/usr/local/bin/claude-automount"],
"/tmp/laptop-exec.sh":["/usr/local/bin/laptop-exec","/usr/local/lib/claude-server/laptop-exec.sh"],
"/tmp/claude-mount.sh":["/usr/local/bin/claude-mount","/usr/local/lib/claude-mount"],
}
for s,ds in m.items():
    data=open(s,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b"\n")
    for d in ds:
        os.makedirs(os.path.dirname(d),exist_ok=True)
        open(d,"wb").write(data); os.chmod(d,0o755); print("ok",d)
print("BINS_DONE")
'@
[IO.File]::WriteAllBytes("$env:TEMP\bins.py", [Text.Encoding]::UTF8.GetBytes($py2.Replace("`r`n","`n").Replace("`r","`n")))
scp -o BatchMode=yes -q "$env:TEMP\bins.py" 'sepidz@192.168.250.70:/tmp/bins.py'
$bw = ((@(
  '#!/bin/bash',
  ('PW=$(echo {0} | base64 -d)' -f $pwB64),
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/bins.py'
) -join "`n") + "`n")
[IO.File]::WriteAllBytes("$env:TEMP\bins.sh", [Text.Encoding]::UTF8.GetBytes($bw))
scp -o BatchMode=yes -q "$env:TEMP\bins.sh" 'sepidz@192.168.250.70:/tmp/bins.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/bins.sh'
Write-Host 'SEPIDZ_DEPLOY_COMPLETE_NO_PROMPT'
