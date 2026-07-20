$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\bump-connect-version.ps1"
. "$root\publish\Get-DeployCredentials.ps1"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Version = '20260717.35'
Set-ConnectVersionInRepo -ProjectRoot $root -Version $Version
Write-Host "VERSION=$Version"

# Probe endpoint resolution
$tmp = Join-Path $env:TEMP 'upd-endpoint-test'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Set-Content (Join-Path $tmp 'connect-version.txt') '20260717.8'
Set-Content (Join-Path $tmp 'connect.ps1') '$ServerIP = "192.168.250.70"'
$probe = @'
param($ScriptDir,$UpdPath)
$raw = Get-Content $UpdPath -Raw
$cut = $raw.IndexOf("if (-not (Get-Command ssh")
Invoke-Expression $raw.Substring(0, $cut)
$ep = Get-ServerEndpoint
Write-Host ("ENDPOINT={0}" -f $ep.Target)
'@
[IO.File]::WriteAllText("$env:TEMP\probe_ep.ps1", $probe)
& powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\probe_ep.ps1" -ScriptDir $tmp -UpdPath "$root\scripts\client\windows\connect-update.ps1"

& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\publish\publish.ps1" -SepidzOnly -SkipVersionBump -SkipServerDeploy
if ($LASTEXITCODE -ne 0) { throw 'publish failed' }

$clientRoot = Get-ChildItem (Join-Path $env:USERPROFILE 'Desktop\claude-publish') -Directory -Filter 'claude-code-sepidz-*' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
  ForEach-Object { Join-Path $_.FullName 'claude-code' }
Write-Host "CLIENT=$clientRoot"
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

# Fix poisoned folder
$bad = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
$goodWin = Join-Path $clientRoot 'windows'
if (Test-Path $bad) {
  Copy-Item (Join-Path $goodWin '*') $bad -Force -Recurse
  Write-Host ("FIXED_BAD ver={0} ip={1}" -f (Get-Content (Join-Path $bad 'connect-version.txt') -Raw).Trim(), [regex]::Match((Get-Content (Join-Path $bad 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value)
}

# Simulate auto-update: local .8 with Sepidz IP -> should become .35 from Sepidz
$sim = Join-Path $env:TEMP 'sepidz-update-sim'
if(Test-Path $sim){Remove-Item $sim -Recurse -Force}
New-Item -ItemType Directory -Force -Path $sim | Out-Null
Copy-Item (Join-Path $goodWin '*') $sim -Force -Recurse
Set-Content (Join-Path $sim 'connect-version.txt') '20260717.8'
Write-Host '=== SIMULATE AUTO-UPDATE ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sim 'connect-update.ps1') -ScriptDir $sim
Write-Host ("SIM_EXIT=$LASTEXITCODE")
$after = (Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim()
$simIp = [regex]::Match((Get-Content (Join-Path $sim 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
Write-Host ("SIM_VER_AFTER=$after SIM_IP_AFTER=$simIp")

$live = ((ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=10 sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt") | Out-String).Trim()
$smartOut=[IO.Path]::GetTempFileName()
$p2=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8','smart@192.168.210.240','cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $smartOut -RedirectStandardError "$smartOut.err"
[void]$p2.WaitForExit(12000)
$smart=((Get-Content $smartOut -Raw)+'').Trim()
Write-Host "SEPIDZ_LIVE=$live SMART_LIVE=$smart"
if ($live -ne $Version) { throw "live mismatch $live" }
if ($after -ne $Version) { throw "sim update failed $after" }
if ($simIp -ne '192.168.250.70') { throw "sim ip $simIp" }
Write-Host 'UPDATE_FIX_OK'
