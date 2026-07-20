$ErrorActionPreference='Stop'
$fail=New-Object System.Collections.Generic.List[string]
function Check([bool]$c,[string]$m){ if($c){Write-Host "OK  $m"} else {Write-Host "FAIL $m"; [void]$script:fail.Add($m)} }
function SshOut($t,$c){ $o=Join-Path $env:TEMP ('s'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.out'); $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err'); if(-not $p.WaitForExit(20000)){try{$p.Kill()}catch{}; return 'TIMEOUT'}; return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'').Trim() }
function RunUpdate($dir){ $log=Join-Path $env:TEMP ('u'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.log'); $p=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $dir 'connect-update.ps1'),'-ScriptDir',$dir) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err'); if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; return @{Ok=$false;Out='TIMEOUT';Ver='';Ip='';Alias=''} }; $out=((Get-Content $log -Raw -ErrorAction SilentlyContinue)+''); return @{Ok=$true;Out=$out;Ver=(Get-Content (Join-Path $dir 'connect-version.txt') -Raw).Trim();Ip=[regex]::Match((Get-Content (Join-Path $dir 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value;Alias=[regex]::Match((Get-Content (Join-Path $dir 'connect.ps1') -Raw),'\$Alias\s*=\s*"([^"]+)"').Groups[1].Value} }

$live=SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
$smart=SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'
Check ($live -eq '20260717.39') "live sepidz .39 ($live)"
Check ($smart -eq '20260717.22') "smart frozen ($smart)"

$src='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'
$good='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code'
Copy-Item (Join-Path $good 'windows\*') (Join-Path $src 'windows') -Force -Recurse
if(Test-Path (Join-Path $src 'mac')){ Copy-Item (Join-Path $good 'mac\*') (Join-Path $src 'mac') -Force -Recurse }
$winReal=Join-Path $src 'windows'
$v=(Get-Content (Join-Path $winReal 'connect-version.txt') -Raw).Trim()
$ip=[regex]::Match((Get-Content (Join-Path $winReal 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
$alias=[regex]::Match((Get-Content (Join-Path $winReal 'connect.ps1') -Raw),'\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
$hasCleanup=Select-String -Path (Join-Path $winReal 'connect-update.ps1') -Pattern 'Safety: never leave nested' -Quiet
Check ($v -eq '20260717.39') "your folder ver .39 ($v)"
Check ($ip -eq '192.168.250.70') "your folder ip ($ip)"
Check ($alias -eq 'claude-server-sepidz') "your folder alias ($alias)"
Check ([bool]$hasCleanup) 'your folder updater has leak cleanup'

$tree=Join-Path $env:TEMP 'sure39-tree'
if(Test-Path $tree){Remove-Item $tree -Recurse -Force}
Copy-Item $src $tree -Recurse -Force
$win=Join-Path $tree 'windows'; $mac=Join-Path $tree 'mac'
Set-Content (Join-Path $win 'connect-version.txt') '20260717.8'
if(Test-Path (Join-Path $mac 'connect-version.txt')){Set-Content (Join-Path $mac 'connect-version.txt') '20260717.8'}
$r=RunUpdate $win
Write-Host $r.Out
Check ($r.Out -match 'sepidz@192\.168\.250\.70') 'source sepidz'
Check ($r.Out -notmatch 'Update source:\s*claude-server(\s|$)') 'not claude-server'
Check ($r.Ver -eq '20260717.39') "update to .39 ($($r.Ver))"
Check ($r.Ver -ne '20260717.22') 'not .22'
Check ($r.Ip -eq '192.168.250.70') 'ip sepidz'
Check ($r.Alias -eq 'claude-server-sepidz') 'alias sepidz'
Check ((Get-Content (Join-Path $mac 'connect-version.txt') -Raw).Trim() -eq '20260717.39') 'mac synced'
Check (-not (Test-Path (Join-Path $win 'mac'))) 'no mac leak'
Check (-not (Test-Path (Join-Path $win 'server'))) 'no server leak'

Set-Content (Join-Path $win 'connect-version.txt') '20260717.22'
$r2=RunUpdate $win
Check (($r2.Ver -eq '20260717.39') -and ($r2.Ip -eq '192.168.250.70')) 'recover from .22'

$r3=RunUpdate $win
Check ($r3.Out -match 'up to date') 'already current'

if($fail.Count -eq 0){ Write-Host 'RESULT=PASS ALL_CHECKS'; exit 0 }
Write-Host "RESULT=FAIL count=$($fail.Count)"
foreach($x in $fail){ Write-Host "FAIL_ITEM: $x" }
exit 1
