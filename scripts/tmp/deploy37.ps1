$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\bump-connect-version.ps1"
. "$root\publish\Get-DeployCredentials.ps1"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Version = '20260717.37'
Set-ConnectVersionInRepo -ProjectRoot $root -Version $Version
Write-Host "VERSION=$Version"

& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\publish\publish.ps1" -SepidzOnly -SkipVersionBump -SkipServerDeploy
if ($LASTEXITCODE -ne 0) { throw 'publish failed' }

$clientRoot = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code'
$pkgVer = (Get-Content (Join-Path $clientRoot 'windows\connect-version.txt') -Raw).Trim()
if ($pkgVer -ne $Version) { throw "pkg $pkgVer != $Version" }

$stage = Join-Path $env:TEMP 'claude-client-bundle-sepidz'
$zip = Join-Path $env:TEMP 'claude-client-bundle-sepidz.zip'
$Win = @('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1','claude-self-heal.sh','claude-automount.sh')
$Mac = @('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh','claude-self-heal.sh','claude-automount.sh')
$Srv = @('laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','claude-self-heal.sh','claude-automount.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json')
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage,(Join-Path $stage 'mac'),(Join-Path $stage 'server') | Out-Null
function Copy1($s,$d){ if(-not(Test-Path $s)){return}; $p=Split-Path $d -Parent; if($p -and -not(Test-Path $p)){New-Item -ItemType Directory -Force -Path $p|Out-Null}; Copy-Item -LiteralPath $s -Destination $d -Force }
foreach($n in $Win){ Copy1 (Join-Path $clientRoot "windows\$n") (Join-Path $stage $n) }
foreach($n in @('claude-self-heal.sh','claude-automount.sh')){ if(-not(Test-Path (Join-Path $stage $n))){ Copy1 (Join-Path $root "scripts\server\$n") (Join-Path $stage $n)} }
foreach($n in $Mac){
  $s = Join-Path $clientRoot "mac\$n"
  if ($n -eq 'connect-update.sh') { $s = Join-Path $root 'scripts\client\mac\connect-update.sh' }
  elseif (-not (Test-Path $s)) { $s = Join-Path $root "scripts\server\$n" }
  Copy1 $s (Join-Path $stage "mac\$n")
}
Copy1 (Join-Path $root 'scripts\client\windows\connect-update.ps1') (Join-Path $stage 'connect-update.ps1')
foreach($rel in $Srv){ Copy1 (Join-Path $root ("scripts\server\"+($rel -replace '/','\'))) (Join-Path $stage ("server\"+($rel -replace '/','\'))) }
if(Test-Path $zip){Remove-Item $zip -Force}
$z=[IO.Compression.ZipFile]::Open($zip,'Create')
try{ Get-ChildItem $stage -Recurse -File | ForEach-Object { $rel=$_.FullName.Substring($stage.Length).TrimStart('\'); $e=$z.CreateEntry($rel.Replace('\','/')); $es=$e.Open(); try{$fs=[IO.File]::Open($_.FullName,'Open','Read','ReadWrite'); try{$fs.CopyTo($es)}finally{$fs.Dispose()}}finally{$es.Dispose()} } } finally{$z.Dispose()}

$remoteDir='.claude-client-deploy'
$pw=Get-SepidzSudoPassword
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=15 sepidz@192.168.250.70 "mkdir -p ~/$remoteDir"
scp -o BatchMode=yes -o ControlMaster=no -q $zip "sepidz@192.168.250.70:~/$remoteDir/bundle.zip"
$inst=[IO.File]::ReadAllText("$root\scripts\server\commands\install-client-bundle.sh").Replace("`r`n","`n").Replace("`r","`n")
[IO.File]::WriteAllBytes("$env:TEMP\install-client-bundle.sh",[Text.Encoding]::UTF8.GetBytes($inst))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\install-client-bundle.sh" "sepidz@192.168.250.70:~/$remoteDir/install-client-bundle.sh"
$lines=@('#!/bin/bash','set -e',('PW=$(echo {0} | base64 -d)' -f $pwB64),('RD="$HOME/{0}"' -f $remoteDir),'python3 - <<"PY"','from pathlib import Path',('p = Path.home() / "{0}" / "install-client-bundle.sh"' -f $remoteDir),'b = p.read_bytes() if p.exists() else b""','if b.startswith(b"\xef\xbb\xbf"): b = b[3:]','p.write_bytes(b.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))','PY','chmod +x "$RD/install-client-bundle.sh"','printf ''%s\n'' "$PW" | sudo -S -p '''' mkdir -p /usr/local/lib/claude-server/commands','printf ''%s\n'' "$PW" | sudo -S -p '''' cp -f "$RD/install-client-bundle.sh" /usr/local/lib/claude-server/commands/install-client-bundle.sh','printf ''%s\n'' "$PW" | sudo -S -p '''' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh','printf ''%s\n'' "$PW" | sudo -S -p '''' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "$RD/bundle.zip"','ec=$?','echo INSTALL_EC=$ec','exit $ec')
[IO.File]::WriteAllBytes("$env:TEMP\sep_inst.sh",[Text.Encoding]::UTF8.GetBytes((($lines -join "`n")+"`n")))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\sep_inst.sh" 'sepidz@192.168.250.70:/tmp/sep_inst.sh'
$out="$env:TEMP\sep_inst.out"
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70','bash /tmp/sep_inst.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if(-not $p.WaitForExit(300000)){throw 'TIMEOUT'}
Write-Host (Get-Content $out -Raw)
if((Get-Content $out -Raw) -notmatch 'INSTALL_EC=0|Done\.'){ throw 'install fail' }

# Refresh poisoned folder only (not self-copy of 20260718)
$bad = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
Copy-Item (Join-Path $clientRoot 'windows\*') $bad -Force -Recurse
Write-Host ("FIXED_BAD ver={0} ip={1}" -f (Get-Content (Join-Path $bad 'connect-version.txt') -Raw).Trim(), [regex]::Match((Get-Content (Join-Path $bad 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value)

$sim = Join-Path $env:TEMP 'sepidz-update-sim37b'
if(Test-Path $sim){Remove-Item $sim -Recurse -Force}
New-Item -ItemType Directory -Force -Path $sim | Out-Null
Copy-Item (Join-Path $clientRoot 'windows\*') $sim -Force -Recurse
Set-Content (Join-Path $sim 'connect-version.txt') '20260717.8'
$log = Join-Path $env:TEMP 'sim37b.log'
$p2 = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $sim 'connect-update.ps1'),'-ScriptDir',$sim) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
if (-not $p2.WaitForExit(180000)) { try{$p2.Kill()}catch{}; throw 'SIM TIMEOUT' }
Write-Host (Get-Content $log -Raw)
$after = (Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim()
$simIp = [regex]::Match((Get-Content (Join-Path $sim 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
$live = ((ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=10 sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt") | Out-String).Trim()
$smart = ((ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=8 smart@192.168.210.240 "cat /usr/local/share/claude-client/connect-version.txt") | Out-String).Trim()
Write-Host "SIM_VER_AFTER=$after SIM_IP=$simIp SEPIDZ_LIVE=$live SMART_LIVE=$smart"
if ($live -ne $Version -or $after -ne $Version -or $simIp -ne '192.168.250.70') { throw 'verify fail' }
Write-Host 'UPDATE_FIX_OK'
