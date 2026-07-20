$ErrorActionPreference = 'Continue'
function R([string]$s){ Write-Host $s }
function SshTimed([string]$Target, [string]$Cmd, [int]$Ms=25000){
  $o = Join-Path $env:TEMP ("da-" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".out")
  $e = "$o.err"
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8','-o','ConnectionAttempts=1',$Target,$Cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if(-not $p.WaitForExit($Ms)){ try{$p.Kill()}catch{}; return @{Ok=$false; Out='TIMEOUT'} }
  Start-Sleep -Milliseconds 40
  $out = ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'').Trim()
  Remove-Item $o,$e -Force -ErrorAction SilentlyContinue
  return @{Ok=$true; Out=$out}
}

R '===1 LIVE==='
foreach($n in @('SEPIDZ','SMART')){
  $t = if($n -eq 'SEPIDZ'){'sepidz@192.168.250.70'}else{'smart@192.168.210.240'}
  R ("[{0}] ver={1}" -f $n,(SshTimed $t 'cat /usr/local/share/claude-client/connect-version.txt').Out)
  R ("[{0}] ip={1}" -f $n,(SshTimed $t 'grep ServerIP /usr/local/share/claude-client/connect.ps1 | head -1').Out)
  R ("[{0}] cv={1}" -f $n,(SshTimed $t 'grep ConnectVersion /usr/local/share/claude-client/connect.ps1 | head -2').Out)
  R ("[{0}] files={1}" -f $n,(SshTimed $t 'find /usr/local/share/claude-client -type f | sort | wc -l').Out)
  R ("[{0}] manifest=`n{1}" -f $n,(SshTimed $t 'cat /usr/local/share/claude-client/manifest.txt').Out)
  R ("[{0}] upd=`n{1}" -f $n,(SshTimed $t 'grep -nE "claude-server|user@IP|Start-Process|Get-ServerEndpoint|Invoke-SshTimed" /usr/local/share/claude-client/connect-update.ps1 | head -25').Out)
}

R '===2 DESKTOP==='
Get-ChildItem 'C:\Users\Smart\Desktop\claude-publish' -Directory -Filter 'claude-code-*' -ErrorAction SilentlyContinue | ForEach-Object {
  $w = Join-Path $_.FullName 'claude-code\windows'
  if(-not (Test-Path $w)){ return }
  $v=(Get-Content (Join-Path $w 'connect-version.txt') -Raw).Trim()
  $ip=[regex]::Match((Get-Content (Join-Path $w 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
  $raw=Get-Content (Join-Path $w 'connect-update.ps1') -Raw
  $kind='OTHER'
  if($raw -match 'Always user@IP'){$kind='FIXED'}
  elseif($raw -match 'claude-server'){$kind='LEGACY'}
  $cv=[regex]::Match($raw,'doesnotmatter')
  $cv2=[regex]::Match((Get-Content (Join-Path $w 'connect.ps1') -Raw),"ConnectVersion\s*=\s*'([^']+)'").Groups[1].Value
  $ok= if($cv2 -eq $v){'OK'} else {"MISMATCH:$cv2"}
  R ("PKG {0} ver={1} ip={2} upd={3} cv={4}" -f $_.Name,$v,$ip,$kind,$ok)
}

R '===3 MANIFEST==='
$man=@(((SshTimed 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/manifest.txt').Out) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object {$_})
R ("total={0} mac={1} server={2} root={3}" -f $man.Count, @($man|?{$_ -like 'mac/*'}).Count, @($man|?{$_ -like 'server/*'}).Count, @($man|?{$_ -notlike 'mac/*' -and $_ -notlike 'server/*'}).Count)
$man | Where-Object {$_ -like 'mac/*' -or $_ -like 'server/*'} | ForEach-Object { R "  $_" }

R '===4 SCENARIOS==='
$goodWin='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\windows'
$fixed='D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1'
function Run-Sim($Label,$StartVer,$Ip,$Upd){
  $sim=Join-Path $env:TEMP ('ds-'+[guid]::NewGuid().ToString('N').Substring(0,6))
  New-Item -ItemType Directory -Force -Path $sim|Out-Null
  Copy-Item (Join-Path $goodWin '*') $sim -Force -Recurse
  Copy-Item $Upd (Join-Path $sim 'connect-update.ps1') -Force
  Set-Content (Join-Path $sim 'connect-version.txt') $StartVer
  $ps1=Get-Content (Join-Path $sim 'connect.ps1') -Raw
  $ps1=[regex]::Replace($ps1,'(?m)^(\s*\$ServerIP\s*=\s*")[^"]+(")',('${1}'+$Ip+'${2}'))
  $ps1=[regex]::Replace($ps1,"ConnectVersion\s*=\s*'[^']+'",("ConnectVersion = '"+$StartVer+"'"))
  [IO.File]::WriteAllText((Join-Path $sim 'connect.ps1'),$ps1)
  $log=Join-Path $env:TEMP ('sl-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.log')
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $p=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $sim 'connect-update.ps1'),'-ScriptDir',$sim) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
  if(-not $p.WaitForExit(120000)){ try{$p.Kill()}catch{}; R "[$Label] TIMEOUT"; return }
  $out=((Get-Content $log -Raw -ErrorAction SilentlyContinue)+'').Trim()
  $after=(Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim()
  $ipOut=[regex]::Match((Get-Content (Join-Path $sim 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
  $src=($out -split "`n" | Where-Object {$_ -match 'Update source|Updated to|unreachable|up to date|via claude-server|remote='} | Select-Object -First 4) -join ' || '
  $leakM=Test-Path (Join-Path $sim 'mac'); $leakS=Test-Path (Join-Path $sim 'server')
  R ("[{0}] {1}/{2} -> ver={3} ip={4} ms={5} leakMac={6} leakSrv={7}" -f $Label,$StartVer,$Ip,$after,$ipOut,$sw.ElapsedMilliseconds,$leakM,$leakS)
  R ("[{0}] {1}" -f $Label,$src)
  if($Ip -eq '192.168.250.70' -and $Label -notlike '*LEGACY*' -and $after -eq '20260717.22'){ R "[$Label] FAIL Smart .22" }
  if($Ip -eq '192.168.250.70' -and $Label -like '*from8*' -and $Label -notlike '*LEGACY*' -and $after -ne '20260717.37'){ R "[$Label] FAIL want .37 got $after" }
  if($Label -like '*LEGACY*' -and $after -eq '20260717.22'){ R "[$Label] REPRO user bug legacy->.22" }
  Remove-Item $sim -Recurse -Force -ErrorAction SilentlyContinue
}
$legacy=Join-Path $env:TEMP 'legacy-upd.ps1'
@'
param([string]$ScriptDir='')
$RemoteBundle='/usr/local/share/claude-client'
Write-Host '  Update source: claude-server'
$o=Join-Path $env:TEMP 'leg.out'; $e=Join-Path $env:TEMP 'leg.err'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8','claude-server',"cat $RemoteBundle/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
[void]$p.WaitForExit(20000)
$remote=((Get-Content $o -Raw)+'').Trim(); $local=(Get-Content (Join-Path $ScriptDir 'connect-version.txt') -Raw).Trim()
Write-Host "  remote=$remote local=$local"
if($remote -and $remote -ne $local){
  $st=Join-Path $ScriptDir '.stg'; if(Test-Path $st){Remove-Item $st -Recurse -Force}; New-Item -ItemType Directory -Path $st|Out-Null
  $p2=Start-Process scp -ArgumentList @('-r','-o','BatchMode=yes','-o','ControlMaster=no','-q',"claude-server:${RemoteBundle}/.",$st) -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\ls.out" -RedirectStandardError "$env:TEMP\ls.err"
  [void]$p2.WaitForExit(120000)
  Get-ChildItem $st -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $ScriptDir $_.Name) -Force }
  Write-Host "  Updated to v$remote (via claude-server)"; exit 2
}
exit 0
'@ | Set-Content $legacy

Run-Sim 'A_fixed_from8' '20260717.8' '192.168.250.70' $fixed
Run-Sim 'B_fixed_from22' '20260717.22' '192.168.250.70' $fixed
Run-Sim 'C_fixed_current' '20260717.37' '192.168.250.70' $fixed
Run-Sim 'D_fixed_smartIP_from8' '20260717.8' '192.168.210.240' $fixed
Run-Sim 'E_LEGACY_from8' '20260717.8' '192.168.250.70' $legacy

R '===5 PACKAGE TREE==='
$pkg=Join-Path $env:TEMP 'deep-pkg-tree'
if(Test-Path $pkg){Remove-Item $pkg -Recurse -Force}
Copy-Item 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code' $pkg -Recurse -Force
$win=Join-Path $pkg 'windows'; $mac=Join-Path $pkg 'mac'
Set-Content (Join-Path $win 'connect-version.txt') '20260717.8'
Set-Content (Join-Path $mac 'connect-version.txt') '20260717.8'
Copy-Item $fixed (Join-Path $win 'connect-update.ps1') -Force
$log=Join-Path $env:TEMP 'deep-pkg.log'
$p=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $win 'connect-update.ps1'),'-ScriptDir',$win) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
if(-not $p.WaitForExit(180000)){ try{$p.Kill()}catch{}; R 'PKG TIMEOUT' } else {
  R ((Get-Content $log -Raw -ErrorAction SilentlyContinue)+'')
  $wv=(Get-Content (Join-Path $win 'connect-version.txt') -Raw).Trim()
  $mv=(Get-Content (Join-Path $mac 'connect-version.txt') -Raw).Trim()
  R ("PKG win={0} siblingMac={1} leakWinMac={2} leakWinSrv={3}" -f $wv,$mv,(Test-Path (Join-Path $win 'mac')),(Test-Path (Join-Path $win 'server')))
  if($mv -eq '20260717.8'){ R 'FINDING: sibling mac/ NOT updated by Windows updater' }
  if(Test-Path (Join-Path $win 'mac')){ R 'FINDING: mac files leaked under windows/mac' }
  if($wv -ne '20260717.37'){ R "FINDING: win did not reach .37 got $wv" } else { R 'PKG win OK .37' }
}

R '===6 SSH ALIASES==='
$cfg=Join-Path $env:USERPROFILE '.ssh\config'
$hosts=@{}; $cur=$null
Get-Content $cfg | ForEach-Object {
  if($_ -match '^\s*Host\s+(.+?)\s*$'){ $cur=($Matches[1].Trim() -split '\s+')[0]; if(-not $hosts.ContainsKey($cur)){$hosts[$cur]=@{}}; return }
  if(-not $cur){return}
  if($_ -match '^\s*HostName\s+(\S+)'){ $hosts[$cur].HostName=$Matches[1] }
  if($_ -match '^\s*User\s+(\S+)'){ $hosts[$cur].User=$Matches[1] }
}
foreach($h in @('claude-server','claude-server-sepidz','claude-design-server')){
  if($hosts.ContainsKey($h)){ R ("Host {0} => {1}@{2}" -f $h,$hosts[$h].User,$hosts[$h].HostName) } else { R "Host $h ABSENT" }
}
R 'CONFIRMED: claude-server=Smart is root cause of Sepidz .8->.22'

R '===7 REPO VERSIONS==='
$rw=(Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
$rm=(Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect-version.txt' -Raw).Trim()
$rp=[regex]::Match((Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Raw),"ConnectVersion\s*=\s*'([^']+)'").Groups[1].Value
R "winVer=$rw macVer=$rm ps1Ver=$rp"
if($rw -ne $rm -or $rw -ne $rp){ R 'FINDING: repo version mismatch' } else { R 'repo aligned' }

R '===8 MAC ALIAS IN PACKAGE==='
$sepMac=Get-Content 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\mac\connect.sh' -Raw
R ("Sepidz mac ALIAS={0} SERVER_IP={1}" -f [regex]::Match($sepMac,'(?m)^ALIAS="([^"]+)"').Groups[1].Value, [regex]::Match($sepMac,'(?m)^SERVER_IP="([^"]+)"').Groups[1].Value)
$repoMac=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh' -Raw
if($repoMac -match 'ALIAS="claude-server"'){ R 'FINDING: repo mac/connect.sh hardcodes ALIAS=claude-server (publish must rewrite for Sepidz)' }

R '===DONE==='
