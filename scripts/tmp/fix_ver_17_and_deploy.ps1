$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\bump-connect-version.ps1"
. "$root\publish\Get-DeployCredentials.ps1"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Stay on 20260717.* — next after .33 that was live before the bad .18 bump
$Version = '20260717.34'
Write-Host "SETTING_VERSION=$Version (NOT 20260718)"
Set-ConnectVersionInRepo -ProjectRoot $root -Version $Version
$got = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
if ($got -ne $Version) { throw "version write failed got=$got" }
Write-Host "REPO_OK=$got"

# Rebuild Sepidz package via publish -SepidzOnly -SkipVersionBump -SkipServerDeploy first (zip only)
Write-Host '=== publish Sepidz package (no auto bump, no auto deploy) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\publish\publish.ps1" -SepidzOnly -SkipVersionBump -SkipServerDeploy
if ($LASTEXITCODE -ne 0) { throw "publish failed $LASTEXITCODE" }

$clientRoot = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260718\claude-code'
# publish folder name uses Get-Date yyyyMMdd for folder — find newest sepidz
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$clientRoot = Get-ChildItem $pub -Directory -Filter 'claude-code-sepidz-*' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
  ForEach-Object { Join-Path $_.FullName 'claude-code' }
Write-Host "CLIENT_ROOT=$clientRoot"
$pkgVer = (Get-Content (Join-Path $clientRoot 'windows\connect-version.txt') -Raw).Trim()
Write-Host "PACKAGE_VER=$pkgVer"
if ($pkgVer -ne $Version) { throw "package version mismatch $pkgVer vs $Version" }

# Stage flat bundle + forward-slash zip
$stage = Join-Path $env:TEMP 'claude-client-bundle-sepidz'
$zip = Join-Path $env:TEMP 'claude-client-bundle-sepidz.zip'
$Win = @('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1','claude-self-heal.sh','claude-automount.sh')
$Mac = @('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh','claude-self-heal.sh','claude-automount.sh')
$Srv = @('laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','claude-self-heal.sh','claude-automount.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json')

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage,(Join-Path $stage 'mac'),(Join-Path $stage 'server') | Out-Null
function Copy1($s,$d){ if(-not(Test-Path $s)){Write-Host "SKIP $s";return}; $p=Split-Path $d -Parent; if($p -and -not(Test-Path $p)){New-Item -ItemType Directory -Force -Path $p|Out-Null}; Copy-Item -LiteralPath $s -Destination $d -Force }
foreach($n in $Win){ Copy1 (Join-Path $clientRoot "windows\$n") (Join-Path $stage $n) }
foreach($n in @('claude-self-heal.sh','claude-automount.sh')){ if(-not(Test-Path (Join-Path $stage $n))){ Copy1 (Join-Path $root "scripts\server\$n") (Join-Path $stage $n) } }
foreach($n in $Mac){
  $s=Join-Path $clientRoot "mac\$n"; if(-not(Test-Path $s)){ $s=Join-Path $root "scripts\server\$n" }
  Copy1 $s (Join-Path $stage "mac\$n")
}
foreach($rel in $Srv){ Copy1 (Join-Path $root ("scripts\server\"+($rel -replace '/','\'))) (Join-Path $stage ("server\"+($rel -replace '/','\'))) }
if(-not(Test-Path (Join-Path $stage 'connect.ps1'))){ throw 'missing connect.ps1' }
if(-not(Test-Path (Join-Path $stage 'mac\connect.sh'))){ throw 'missing mac/connect.sh' }

if(Test-Path $zip){ Remove-Item $zip -Force }
$z=[System.IO.Compression.ZipFile]::Open($zip,[System.IO.Compression.ZipArchiveMode]::Create)
try{
  Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $rel=$_.FullName.Substring($stage.Length).TrimStart('\')
    $e=$z.CreateEntry($rel.Replace('\','/'))
    $es=$e.Open(); try{ $fs=[IO.File]::Open($_.FullName,'Open','Read','ReadWrite'); try{$fs.CopyTo($es)} finally{$fs.Dispose()} } finally{$es.Dispose()}
  }
} finally { $z.Dispose() }
Write-Host "ZIP=$((Get-Item $zip).Length)"

# Deploy with hardcoded password path (Get-SepidzSudoPassword)
$remoteDir='.claude-client-deploy'
$pw = Get-SepidzSudoPassword
if([string]::IsNullOrWhiteSpace($pw)){ throw 'no sepidz password' }
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))

ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=15 sepidz@192.168.250.70 "mkdir -p ~/$remoteDir"
scp -o BatchMode=yes -o ControlMaster=no -q $zip "sepidz@192.168.250.70:~/$remoteDir/bundle.zip"
$inst=[IO.File]::ReadAllText("$root\scripts\server\commands\install-client-bundle.sh").Replace("`r`n","`n").Replace("`r","`n")
[IO.File]::WriteAllBytes("$env:TEMP\install-client-bundle.sh",[Text.Encoding]::UTF8.GetBytes($inst))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\install-client-bundle.sh" "sepidz@192.168.250.70:~/$remoteDir/install-client-bundle.sh"

$lines=@(
  '#!/bin/bash','set -e',
  ('PW=$(echo {0} | base64 -d)' -f $pwB64),
  ('RD="$HOME/{0}"' -f $remoteDir),
  'python3 - <<"PY"',
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
  'ec=$?','echo INSTALL_EC=$ec','exit $ec'
)
[IO.File]::WriteAllBytes("$env:TEMP\sep_inst.sh",[Text.Encoding]::UTF8.GetBytes((($lines -join "`n")+"`n")))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\sep_inst.sh" 'sepidz@192.168.250.70:/tmp/sep_inst.sh'

Write-Host '=== INSTALLING ON SEPIDZ (password, no prompt) ==='
$out="$env:TEMP\sep_inst.out"
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','-o','ServerAliveInterval=5','-o','ServerAliveCountMax=12','sepidz@192.168.250.70','bash /tmp/sep_inst.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if(-not $p.WaitForExit(300000)){ try{$p.Kill()}catch{}; throw 'TIMEOUT' }
$txt=(Get-Content $out -Raw -EA SilentlyContinue)+''
Write-Host $txt
Write-Host ((Get-Content "$out.err" -Raw -EA SilentlyContinue)+'')
if($txt -notmatch 'INSTALL_EC=0' -and $txt -notmatch 'Done\.'){ throw 'install failed' }

# verify
function SshT($t,$c,$s=20){
  $o=[IO.Path]::GetTempFileName()
  $pp=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=10',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.err"
  if(-not $pp.WaitForExit($s*1000)){ try{$pp.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -EA SilentlyContinue)+'').Trim()
}
$sep=SshT 'sepidz@192.168.250.70' "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt"
$smart=SshT 'smart@192.168.210.240' "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt"
Write-Host "SEPIDZ_LIVE=$sep"
Write-Host "SMART_LIVE=$smart"
if($sep -ne $Version){ throw "Sepidz still $sep want $Version" }
if($smart -ne '20260717.22'){ Write-Host "WARN smart=$smart" }
Write-Host 'DEPLOY_17_OK'
