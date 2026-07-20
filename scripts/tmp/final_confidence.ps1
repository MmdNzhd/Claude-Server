$ErrorActionPreference='Continue'
$fail=0
function Ok($m){ Write-Host ("OK  " + $m) -ForegroundColor Green }
function Bad($m){ Write-Host ("BAD " + $m) -ForegroundColor Red; $script:fail++ }

Write-Host '=== 1) VERSIONS ===' -ForegroundColor Cyan
$src=(Get-Content scripts\client\windows\connect-version.txt -Raw).Trim()
$cv=([regex]::Match((Get-Content scripts\client\windows\connect.ps1 -Raw),"ConnectVersion = '([^']+)'")).Groups[1].Value
if($src -eq '20260719.20' -and $cv -eq $src){ Ok "source=$src" } else { Bad "source txt=$src ps1=$cv" }

function V([string]$t){
  $o=Join-Path $env:TEMP ('fc-' + ($t -replace '[^a-z0-9]','') + '.txt')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',$t,"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e')
  if(-not $p.WaitForExit(15000)){ try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -EA SilentlyContinue)+'').Trim()
}
$sep=V 'sepidz@192.168.250.70'
$sma=V 'smart@192.168.210.240'
if($sep -eq '20260719.20'){ Ok "Sepidz server=$sep" } else { Bad "Sepidz=$sep" }
if($sma -eq '20260717.22'){ Ok "Smart frozen=$sma" } else { Bad "Smart=$sma (MUST stay .22)" }

$pkg="$env:USERPROFILE\Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows"
$pkgVer=(Get-Content (Join-Path $pkg 'connect-version.txt') -Raw).Trim()
if($pkgVer -eq '20260719.20'){ Ok "package=$pkgVer" } else { Bad "package=$pkgVer" }

Write-Host ''
Write-Host '=== 2) PARSE ===' -ForegroundColor Cyan
foreach($f in @('scripts\client\windows\connect.ps1','scripts\client\git-mode.ps1','scripts\client\connect-ui.ps1','scripts\client\windows\connect-update.ps1')){
  $e=$null;$t=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f),[ref]$t,[ref]$e)
  if($e -and $e.Count){ Bad ("parse $f : "+$e[0].ToString()) } else { Ok ("parse $f") }
}

Write-Host ''
Write-Host '=== 3) SPEED FIXES PRESENT + MUX ABSENT ===' -ForegroundColor Cyan
$checks=@(
  @{f='scripts\client\git-mode.ps1'; p='one SSH reads conf'; n='warn batch'; want=$true},
  @{f='scripts\client\git-mode.ps1'; p='skip_duplicate'; n='push dedupe'; want=$true},
  @{f='scripts\client\git-mode.ps1'; p='preserve+write+self-heal in ONE SSH'; n='push one-ssh'; want=$true},
  @{f='scripts\client\windows\connect.ps1'; p='ControlMaster=auto'; n='NO broken mux'; want=$false},
  @{f='scripts\client\windows\connect.ps1'; p='ClearAllForwardings=yes'; n='ClearAllForwardings kept'; want=$true},
  @{f='scripts\client\windows\connect-update.ps1'; p='attempt -le 3'; n='update retry x3'; want=$true},
  @{f='scripts\client\windows\connect-update.ps1'; p='TimeoutMs 20000 -RequireStdout'; n='update timeout 20s'; want=$true},
  @{f='scripts\client\windows\connect-update.ps1'; p='TimeoutMs 8000 -RequireStdout'; n='NO shortened update timeout'; want=$false},
  @{f='scripts\client\connect-ui.ps1'; p='Enter-ConnectSingleInstance'; n='mutex'; want=$true},
  @{f='scripts\client\connect-ui.ps1'; p='LastConnectLogSyncOk'; n='no False spam'; want=$true},
  @{f='scripts\client\connect-ui.ps1'; p='Invoke-ConnectLogProcTimed'; n='log sync timed'; want=$true},
  @{f='scripts\client\windows\connect.bat'; p='CLAUDE_CONNECT_RUN_ID'; n='run id correlation'; want=$true}
)
foreach($c in $checks){
  $hit=Select-String -Path $c.f -Pattern $c.p -SimpleMatch -Quiet
  if($hit -eq $c.want){ Ok $c.n } else { Bad ($c.n + " hit=$hit want=$($c.want)") }
}

Write-Host ''
Write-Host '=== 4) PACKAGE == KEY FILES / SEPIDZ PATCH ===' -ForegroundColor Cyan
$cp=Get-Content (Join-Path $pkg 'connect.ps1') -Raw
if($cp -match 'claude-server-sepidz'){ Ok 'package alias sepidz' } else { Bad 'package alias' }
if($cp -match '192\.168\.250\.70'){ Ok 'package IP 250.70' } else { Bad 'package IP' }
if($cp -notmatch '192\.168\.210\.240'){ Ok 'package no Smart IP' } else { Bad 'package has Smart IP' }
if($cp -notmatch 'ControlMaster=auto'){ Ok 'package no mux' } else { Bad 'package still has mux' }
$gmPkg=Select-String -Path (Join-Path $pkg 'git-mode.ps1') -Pattern 'skip_duplicate' -SimpleMatch -Quiet
if($gmPkg){ Ok 'package has push dedupe' } else { Bad 'package missing dedupe' }
$updPkg=Select-String -Path (Join-Path $pkg 'connect-update.ps1') -Pattern 'attempt -le 3' -SimpleMatch -Quiet
if($updPkg){ Ok 'package update retry x3' } else { Bad 'package update retry' }

Write-Host ''
Write-Host '=== 5) REMOTE BUNDLE SPOT ===' -ForegroundColor Cyan
$cmd=@'
echo VER=$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)
echo DEDUPE=$(grep -c skip_duplicate /usr/local/share/claude-client/git-mode.ps1)
echo BATCH=$(grep -c 'ONE SSH' /usr/local/share/claude-client/git-mode.ps1)
echo MUX=$(grep -c 'ControlMaster=auto' /usr/local/share/claude-client/connect.ps1 || true)
echo RETRY3=$(grep -c 'attempt -le 3' /usr/local/share/claude-client/connect-update.ps1)
echo ALIAS=$(grep -c claude-server-sepidz /usr/local/share/claude-client/connect.ps1)
echo SMARTIP=$(grep -c 192.168.210.240 /usr/local/share/claude-client/connect.ps1 || true)
'@
$out=Join-Path $env:TEMP 'fc-remote.txt'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','sepidz@192.168.250.70',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.e')
if(-not $p.WaitForExit(20000)){ Bad 'remote timeout' }
else {
  Get-Content $out | ForEach-Object {
    Write-Host ("    " + $_)
    if($_ -match '^VER=(.+)$'){ if($Matches[1] -eq '20260719.20'){ Ok 'remote VER' } else { Bad "remote VER=$($Matches[1])" } }
    elseif($_ -match '^DEDUPE=(\d+)$'){ if([int]$Matches[1] -ge 1){ Ok 'remote dedupe' } else { Bad 'remote dedupe=0' } }
    elseif($_ -match '^BATCH=(\d+)$'){ if([int]$Matches[1] -ge 1){ Ok 'remote batch' } else { Bad 'remote batch=0' } }
    elseif($_ -match '^MUX=(\d+)$'){ if([int]$Matches[1] -eq 0){ Ok 'remote no mux' } else { Bad 'remote has mux' } }
    elseif($_ -match '^RETRY3=(\d+)$'){ if([int]$Matches[1] -ge 1){ Ok 'remote retry3' } else { Bad 'remote retry3=0' } }
    elseif($_ -match '^ALIAS=(\d+)$'){ if([int]$Matches[1] -ge 1){ Ok 'remote alias' } else { Bad 'remote alias=0' } }
    elseif($_ -match '^SMARTIP=(\d+)$'){ if([int]$Matches[1] -eq 0){ Ok 'remote no Smart IP' } else { Bad 'remote Smart IP present' } }
  }
}

Write-Host ''
Write-Host '=== 6) LIVE CONNECT PROCS ===' -ForegroundColor Cyan
$procs=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'connect\.ps1' })
if($procs.Count -eq 0){ Ok 'no connect.ps1 running' }
else {
  foreach($pr in $procs){
    $cl=$pr.CommandLine; if($cl.Length -gt 160){$cl=$cl.Substring(0,160)}
    if($cl -match 'claude-code-client'){ Bad ("Smart-client still running: $cl") }
    else { Ok ("running: $cl") }
  }
}

Write-Host ''
Write-Host '=== SUMMARY ===' -ForegroundColor Cyan
if($fail -eq 0){ Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green } else { Write-Host ("FAILURES=$fail") -ForegroundColor Red }
exit $fail
