$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$expected = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
$clientRoot = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260718\claude-code'
$stage = Join-Path $env:TEMP 'claude-client-bundle-sepidz'
$zip = Join-Path $env:TEMP 'claude-client-bundle-sepidz.zip'
$remoteDir = '.claude-client-deploy'
Write-Host "expected=$expected"

$Win = @('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1','claude-self-heal.sh','claude-automount.sh')
$Mac = @('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh','claude-self-heal.sh','claude-automount.sh')
$Srv = @('laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','claude-self-heal.sh','claude-automount.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json')

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage,(Join-Path $stage 'mac'),(Join-Path $stage 'server') | Out-Null

function Copy1($src,$dst) {
  $d = Split-Path $dst -Parent
  if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  if (-not (Test-Path $src)) { Write-Host "SKIP $src"; return }
  Copy-Item -LiteralPath $src -Destination $dst -Force
}

foreach ($n in $Win) { Copy1 (Join-Path $clientRoot "windows\$n") (Join-Path $stage $n) }
# heal scripts may only be under windows from publish
foreach ($n in @('claude-self-heal.sh','claude-automount.sh')) {
  if (-not (Test-Path (Join-Path $stage $n))) {
    Copy1 (Join-Path $root "scripts\server\$n") (Join-Path $stage $n)
  }
}
foreach ($n in $Mac) {
  $src = Join-Path $clientRoot "mac\$n"
  if (-not (Test-Path $src)) { $src = Join-Path $root "scripts\server\$n" }
  if (-not (Test-Path $src) -and $n -like 'connect*') { $src = Join-Path $clientRoot "mac\$n" }
  Copy1 $src (Join-Path $stage "mac\$n")
}
foreach ($rel in $Srv) {
  Copy1 (Join-Path $root ("scripts\server\" + ($rel -replace '/','\'))) (Join-Path $stage ("server\" + ($rel -replace '/','\')))
}
if (-not (Test-Path (Join-Path $stage 'connect.ps1'))) { throw 'stage missing connect.ps1' }
if (-not (Test-Path (Join-Path $stage 'mac\connect.sh'))) { throw 'stage missing mac/connect.sh' }

if (Test-Path $zip) { Remove-Item $zip -Force }
$z = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem -Path $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length).TrimStart('\')
    $entry = $z.CreateEntry($rel.Replace('\', '/'))
    $es = $entry.Open()
    try {
      $fs = [System.IO.File]::Open($_.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
      try { $fs.CopyTo($es) } finally { $fs.Dispose() }
    } finally { $es.Dispose() }
  }
} finally { $z.Dispose() }
Write-Host "zip=$((Get-Item $zip).Length)"
# sanity list
Add-Type -AssemblyName System.IO.Compression.FileSystem
$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
  $names = $check.Entries | ForEach-Object { $_.FullName }
  if ($names -notcontains 'mac/connect.sh') { throw ('zip missing mac/connect.sh; has=' + (($names | Select-Object -First 20) -join ',')) }
  if ($names -notcontains 'connect.ps1') { throw 'zip missing connect.ps1' }
  Write-Host ('zip_entries_ok n=' + $names.Count)
} finally { $check.Dispose() }

ssh -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "mkdir -p ~/$remoteDir"
scp -o BatchMode=yes -q $zip "sepidz@192.168.250.70:~/$remoteDir/bundle.zip"
$inst = [IO.File]::ReadAllText("$root\scripts\server\commands\install-client-bundle.sh").Replace("`r`n","`n").Replace("`r","`n")
[IO.File]::WriteAllBytes("$env:TEMP\install-client-bundle.sh", [Text.Encoding]::UTF8.GetBytes($inst))
scp -o BatchMode=yes -q "$env:TEMP\install-client-bundle.sh" "sepidz@192.168.250.70:~/$remoteDir/install-client-bundle.sh"
Write-Host 'UPLOADED'

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$lines = @(
  '#!/bin/bash','set -e',
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
  'echo REMOTE_VER=$(tr -d ''\r\n'' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null || true)',
  'exit $ec'
)
[IO.File]::WriteAllBytes("$env:TEMP\sep_install.sh", [Text.Encoding]::UTF8.GetBytes((($lines -join "`n") + "`n")))
scp -o BatchMode=yes -q "$env:TEMP\sep_install.sh" 'sepidz@192.168.250.70:/tmp/sep_install.sh'

$out="$env:TEMP\sep_out.txt"
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ServerAliveInterval=5','-o','ServerAliveCountMax=12','sepidz@192.168.250.70','bash /tmp/sep_install.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(300000)) { try{$p.Kill()}catch{}; throw 'TIMEOUT' }
Write-Host '--- stdout ---'; Get-Content $out -Raw -EA SilentlyContinue
Write-Host '--- stderr ---'; Get-Content "$out.err" -Raw -EA SilentlyContinue
Write-Host "ssh_exit=$($p.ExitCode)"
if ($p.ExitCode -ne 0) { throw "install failed $($p.ExitCode)" }

$sepVer=(ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
$smartOut="$env:TEMP\smv.txt"
$p2=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','smart@192.168.210.240',"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $smartOut -RedirectStandardError "$smartOut.err"
[void]$p2.WaitForExit(12000)
$smartVer=if(Test-Path $smartOut){(Get-Content $smartOut -Raw).Trim()}else{'?'}
Write-Host "SEPIDZ_LIVE=$sepVer"
Write-Host "SMART_LIVE=$smartVer"
if ($sepVer -ne $expected) { throw "mismatch got=$sepVer want=$expected" }

foreach ($pair in @(
  @("$root\scripts\server\claude-self-heal.sh","/tmp/claude-self-heal.sh"),
  @("$root\scripts\server\laptop-exec-setup.sh","/tmp/laptop-exec-setup.sh"),
  @("$root\scripts\server\claude-automount.sh","/tmp/claude-automount.sh"),
  @("$root\scripts\server\laptop-exec.sh","/tmp/laptop-exec.sh"),
  @("$root\scripts\server\claude-mount.sh","/tmp/claude-mount.sh")
)) { scp -o BatchMode=yes -q $pair[0] ("sepidz@192.168.250.70:"+$pair[1]) }
$py = "import os,pwd`nm={`"/tmp/claude-self-heal.sh`":[`"/usr/local/bin/claude-self-heal`"],`"/tmp/laptop-exec-setup.sh`":[`"/usr/local/bin/laptop-exec-setup`"],`"/tmp/claude-automount.sh`":[`"/usr/local/bin/claude-automount`"],`"/tmp/laptop-exec.sh`":[`"/usr/local/bin/laptop-exec`",`"/usr/local/lib/claude-server/laptop-exec.sh`"],`"/tmp/claude-mount.sh`":[`"/usr/local/bin/claude-mount`",`"/usr/local/lib/claude-mount`"]}`nfor s,ds in m.items():`n data=open(s,'rb').read().replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n')`n for d in ds:`n  os.makedirs(os.path.dirname(d),exist_ok=True); open(d,'wb').write(data); os.chmod(d,0o755); print('ok',d)`nprint('BINS_OK')`n"
# write bins.py cleanly via lines
$pyLines = @(
'import os,pwd',
'm={',
'"/tmp/claude-self-heal.sh":["/usr/local/bin/claude-self-heal"],',
'"/tmp/laptop-exec-setup.sh":["/usr/local/bin/laptop-exec-setup"],',
'"/tmp/claude-automount.sh":["/usr/local/bin/claude-automount"],',
'"/tmp/laptop-exec.sh":["/usr/local/bin/laptop-exec","/usr/local/lib/claude-server/laptop-exec.sh"],',
'"/tmp/claude-mount.sh":["/usr/local/bin/claude-mount","/usr/local/lib/claude-mount"],',
'}',
'for s,ds in m.items():',
'    data=open(s,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b"\n")',
'    for d in ds:',
'        os.makedirs(os.path.dirname(d),exist_ok=True)',
'        open(d,"wb").write(data); os.chmod(d,0o755); print("ok",d)',
'print("BINS_OK")'
)
[IO.File]::WriteAllBytes("$env:TEMP\bins.py", [Text.Encoding]::UTF8.GetBytes((($pyLines -join "`n")+"`n")))
scp -o BatchMode=yes -q "$env:TEMP\bins.py" 'sepidz@192.168.250.70:/tmp/bins.py'
$bw = ((@('#!/bin/bash',('PW=$(echo {0} | base64 -d)' -f $pwB64),'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/bins.py') -join "`n")+"`n")
[IO.File]::WriteAllBytes("$env:TEMP\bins.sh", [Text.Encoding]::UTF8.GetBytes($bw))
scp -o BatchMode=yes -q "$env:TEMP\bins.sh" 'sepidz@192.168.250.70:/tmp/bins.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/bins.sh'
Write-Host 'SEPIDZ_DEPLOY_COMPLETE_NO_PROMPT'
