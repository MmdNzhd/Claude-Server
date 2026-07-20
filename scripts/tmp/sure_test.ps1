$ErrorActionPreference = 'Stop'
$fail = New-Object System.Collections.Generic.List[string]
function Check([bool]$cond, [string]$msg) {
  if ($cond) { Write-Host "OK  $msg" } else { Write-Host "FAIL $msg"; [void]$script:fail.Add($msg) }
}
function SshOut([string]$t, [string]$c) {
  $o = Join-Path $env:TEMP ('s'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.out')
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8','-o','ConnectionAttempts=1',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  if (-not $p.WaitForExit(20000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'').Trim()
}
function RunUpdate([string]$dir) {
  $log = Join-Path $env:TEMP ('u'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.log')
  $p = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $dir 'connect-update.ps1'),'-ScriptDir',$dir) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
  if (-not $p.WaitForExit(120000)) { try{$p.Kill()}catch{}; return @{ Ok=$false; Out='TIMEOUT'; Ver=''; Ip=''; Alias='' } }
  $out = ((Get-Content $log -Raw -ErrorAction SilentlyContinue)+'')
  $ver = (Get-Content (Join-Path $dir 'connect-version.txt') -Raw).Trim()
  $ip = [regex]::Match((Get-Content (Join-Path $dir 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
  $alias = [regex]::Match((Get-Content (Join-Path $dir 'connect.ps1') -Raw),'\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
  return @{ Ok=$true; Out=$out; Ver=$ver; Ip=$ip; Alias=$alias }
}

Write-Host '=== 1 LIVE ==='
$liveS = SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
$liveSmart = SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'
$liveIp = SshOut 'sepidz@192.168.250.70' 'grep ServerIP /usr/local/share/claude-client/connect.ps1 | head -1'
Check ($liveS -eq '20260717.38') "Sepidz live .38 (got $liveS)"
Check ($liveSmart -eq '20260717.22') "Smart frozen .22 (got $liveSmart)"
Check ($liveIp -match '192\.168\.250\.70') "Sepidz live IP 250.70"

Write-Host '=== 2 YOUR FOLDER ==='
$folder = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
Check (Test-Path $folder) 'folder exists'
$v = (Get-Content (Join-Path $folder 'connect-version.txt') -Raw).Trim()
$ip = [regex]::Match((Get-Content (Join-Path $folder 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
$alias = [regex]::Match((Get-Content (Join-Path $folder 'connect.ps1') -Raw),'\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
$updRaw = Get-Content (Join-Path $folder 'connect-update.ps1') -Raw
Check ($v -eq '20260717.38') "folder ver .38 (got $v)"
Check ($ip -eq '192.168.250.70') "folder ip 250.70 (got $ip)"
Check ($alias -eq 'claude-server-sepidz') "folder alias sepidz (got $alias)"
Check ($updRaw -match 'Always user@IP') 'folder updater FIXED'
Check ($updRaw -match 'Start-Process') 'folder updater uses Start-Process'
Check (Test-Path (Join-Path $folder 'connect.bat')) 'connect.bat present'
$bat = Get-Content (Join-Path $folder 'connect.bat') -Raw
Check ($bat -match 'connect-update\.ps1') 'connect.bat calls updater'

Write-Host '=== 3 UPDATE .8 TO .38 FROM YOUR FILES ==='
$sim = Join-Path $env:TEMP 'sure-sepidz-20260717'
if (Test-Path $sim) { Remove-Item $sim -Recurse -Force }
New-Item -ItemType Directory -Force -Path $sim | Out-Null
Copy-Item (Join-Path $folder '*') $sim -Force -Recurse
Set-Content (Join-Path $sim 'connect-version.txt') '20260717.8'
$r = RunUpdate $sim
Write-Host $r.Out
Check ($r.Ok) 'update finished'
Check ($r.Out -match 'Update source:\s*sepidz@192\.168\.250\.70') 'source sepidz@250.70'
Check ($r.Out -notmatch 'Update source:\s*claude-server(\s|$)') 'not bare claude-server'
Check ($r.Out -notmatch '210\.240') 'no Smart IP in output'
Check ($r.Ver -eq '20260717.38') "got .38 (got $($r.Ver))"
Check ($r.Ver -ne '20260717.22') 'not Smart .22'
Check ($r.Ip -eq '192.168.250.70') "IP 250.70 (got $($r.Ip))"
Check ($r.Alias -eq 'claude-server-sepidz') "alias sepidz (got $($r.Alias))"
Check (-not (Test-Path (Join-Path $sim 'mac'))) 'no mac leak'
Check (-not (Test-Path (Join-Path $sim 'server'))) 'no server leak'

Write-Host '=== 4 RECOVER FROM .22 STAMP ==='
$sim2 = Join-Path $env:TEMP 'sure-from22'
if (Test-Path $sim2) { Remove-Item $sim2 -Recurse -Force }
New-Item -ItemType Directory -Force -Path $sim2 | Out-Null
Copy-Item (Join-Path $folder '*') $sim2 -Force -Recurse
Set-Content (Join-Path $sim2 'connect-version.txt') '20260717.22'
$r2 = RunUpdate $sim2
Check ($r2.Out -match 'sepidz@192\.168\.250\.70') 'from22 source Sepidz'
Check ($r2.Ver -eq '20260717.38') "from22 -> .38 (got $($r2.Ver))"
Check ($r2.Ip -eq '192.168.250.70') 'from22 IP Sepidz'

Write-Host '=== 5 PACKAGE TREE WIN+MAC ==='
$tree = Join-Path $env:TEMP 'sure-pkg-tree'
if (Test-Path $tree) { Remove-Item $tree -Recurse -Force }
Copy-Item 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code' $tree -Recurse -Force
$win = Join-Path $tree 'windows'
$mac = Join-Path $tree 'mac'
Set-Content (Join-Path $win 'connect-version.txt') '20260717.8'
Set-Content (Join-Path $mac 'connect-version.txt') '20260717.8'
$r3 = RunUpdate $win
$macVer = (Get-Content (Join-Path $mac 'connect-version.txt') -Raw).Trim()
$macAlias = [regex]::Match((Get-Content (Join-Path $mac 'connect.sh') -Raw),'(?m)^ALIAS="([^"]+)"').Groups[1].Value
Check ($r3.Ver -eq '20260717.38') 'tree win .38'
Check ($macVer -eq '20260717.38') "tree mac .38 (got $macVer)"
Check ($macAlias -eq 'claude-server-sepidz') "tree mac alias (got $macAlias)"
Check (-not (Test-Path (Join-Path $win 'mac'))) 'tree no mac leak'
Check (-not (Test-Path (Join-Path $win 'server'))) 'tree no server leak'

Write-Host '=== 6 ALIAS TRAP PROOF ==='
$cfg = Join-Path $env:USERPROFILE '.ssh\config'
$hn = 'MISSING'
$cur = $null
Get-Content $cfg | ForEach-Object {
  if ($_ -match '^\s*Host\s+(.+)$') { $cur = ($Matches[1].Trim() -split '\s+')[0]; return }
  if ($cur -eq 'claude-server' -and $_ -match '^\s*HostName\s+(\S+)') { if ($hn -eq 'MISSING') { $hn = $Matches[1] } }
}
Check ($hn -eq '192.168.210.240') "claude-server still Smart ($hn) - trap still there"
Check ($r.Out -notmatch 'Update source:\s*claude-server(\s|$)') 'fixed path avoided trap'

Write-Host ''
if ($fail.Count -eq 0) {
  Write-Host 'RESULT=PASS ALL_CHECKS'
  exit 0
}
Write-Host ("RESULT=FAIL count=$($fail.Count)")
foreach ($x in $fail) { Write-Host ("FAIL_ITEM: $x") }
exit 1
