$ErrorActionPreference = 'Stop'
$fail = New-Object System.Collections.Generic.List[string]
function Check([bool]$cond, [string]$msg) {
  if ($cond) { Write-Host "OK  $msg" } else { Write-Host "FAIL $msg"; [void]$script:fail.Add($msg) }
}
function SshOut([string]$t, [string]$c) {
  $o = Join-Path $env:TEMP ('s'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.out')
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  if (-not $p.WaitForExit(20000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'').Trim()
}
function RunUpdate([string]$dir) {
  $log = Join-Path $env:TEMP ('u'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.log')
  $p = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $dir 'connect-update.ps1'),'-ScriptDir',$dir) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
  if (-not $p.WaitForExit(120000)) { try{$p.Kill()}catch{}; return @{ Ok=$false; Out='TIMEOUT'; Ver=''; Ip=''; Alias='' } }
  $out = ((Get-Content $log -Raw -ErrorAction SilentlyContinue)+'')
  return @{
    Ok = $true
    Out = $out
    Ver = (Get-Content (Join-Path $dir 'connect-version.txt') -Raw).Trim()
    Ip = [regex]::Match((Get-Content (Join-Path $dir 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
    Alias = [regex]::Match((Get-Content (Join-Path $dir 'connect.ps1') -Raw),'\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
  }
}

$srcPkg = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'
Write-Host '=== LIVE ==='
$liveS = SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
$liveSmart = SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'
Check ($liveS -eq '20260717.38') "live sepidz .38 ($liveS)"
Check ($liveSmart -eq '20260717.22') "live smart .22 ($liveSmart)"

Write-Host '=== YOUR REAL FOLDER ==='
$winReal = Join-Path $srcPkg 'windows'
$v = (Get-Content (Join-Path $winReal 'connect-version.txt') -Raw).Trim()
$ip = [regex]::Match((Get-Content (Join-Path $winReal 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
$alias = [regex]::Match((Get-Content (Join-Path $winReal 'connect.ps1') -Raw),'\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
Check ($v -eq '20260717.38' -and $ip -eq '192.168.250.70' -and $alias -eq 'claude-server-sepidz') "real folder ready ver/ip/alias ($v / $ip / $alias)"

Write-Host '=== COPY YOUR PACKAGE TREE THEN UPDATE .8 -> .38 ==='
$tree = Join-Path $env:TEMP 'sure-real-tree'
if (Test-Path $tree) { Remove-Item $tree -Recurse -Force }
Copy-Item $srcPkg $tree -Recurse -Force
$win = Join-Path $tree 'windows'
$mac = Join-Path $tree 'mac'
Set-Content (Join-Path $win 'connect-version.txt') '20260717.8'
if (Test-Path (Join-Path $mac 'connect-version.txt')) { Set-Content (Join-Path $mac 'connect-version.txt') '20260717.8' }
$r = RunUpdate $win
Write-Host $r.Out
$macVer = if (Test-Path (Join-Path $mac 'connect-version.txt')) { (Get-Content (Join-Path $mac 'connect-version.txt') -Raw).Trim() } else { 'NO_MAC' }
Check ($r.Ok) 'finished'
Check ($r.Out -match 'Update source:\s*sepidz@192\.168\.250\.70') 'source sepidz@250.70'
Check ($r.Out -notmatch 'Update source:\s*claude-server(\s|$)') 'not claude-server alias'
Check ($r.Out -notmatch '210\.240') 'no smart IP'
Check ($r.Ver -eq '20260717.38') "win -> .38 ($($r.Ver))"
Check ($r.Ver -ne '20260717.22') 'not .22'
Check ($r.Ip -eq '192.168.250.70') "ip stayed ($($r.Ip))"
Check ($r.Alias -eq 'claude-server-sepidz') "alias stayed ($($r.Alias))"
Check ($macVer -eq '20260717.38' -or $macVer -eq 'NO_MAC') "mac sibling synced ($macVer)"
Check (-not (Test-Path (Join-Path $win 'mac'))) 'no windows/mac leak'
Check (-not (Test-Path (Join-Path $win 'server'))) 'no windows/server leak'

Write-Host '=== RECOVER FROM .22 ON SAME TREE ==='
Set-Content (Join-Path $win 'connect-version.txt') '20260717.22'
$r2 = RunUpdate $win
Check ($r2.Out -match 'sepidz@192\.168\.250\.70') 'from22 source sepidz'
Check ($r2.Ver -eq '20260717.38') "from22 -> .38 ($($r2.Ver))"
Check ($r2.Ip -eq '192.168.250.70') 'from22 ip sepidz'

Write-Host '=== ALREADY CURRENT ==='
$r3 = RunUpdate $win
Check ($r3.Out -match 'up to date') 'reports up to date'
Check ($r3.Ver -eq '20260717.38') 'stays .38'

Write-Host ''
if ($fail.Count -eq 0) { Write-Host 'RESULT=PASS ALL_CHECKS'; exit 0 }
Write-Host "RESULT=FAIL count=$($fail.Count)"
foreach ($x in $fail) { Write-Host "FAIL_ITEM: $x" }
exit 1
