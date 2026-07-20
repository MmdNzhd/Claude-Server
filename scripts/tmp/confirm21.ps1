$ErrorActionPreference='Stop'
$fail=0
function Ok($m){Write-Host "OK  $m" -ForegroundColor Green}
function Bad($m){Write-Host "BAD $m" -ForegroundColor Red; $script:fail++}

$src=(Get-Content scripts\client\windows\connect-version.txt -Raw).Trim()
$cv=([regex]::Match((Get-Content scripts\client\windows\connect.ps1 -Raw),"ConnectVersion = '([^']+)'")).Groups[1].Value
if($src -eq '20260719.21' -and $cv -eq $src){Ok "source=$src"}else{Bad "src=$src cv=$cv"}

function V($t){$o=Join-Path $env:TEMP 'c21.txt';$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',$t,"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e');if(-not $p.WaitForExit(12000)){try{$p.Kill()}catch{};return 'TIMEOUT'};((Get-Content $o -Raw)+'').Trim()}
$sep=V 'sepidz@192.168.250.70'; $sma=V 'smart@192.168.210.240'
if($sep -eq '20260719.21'){Ok "Sepidz=$sep"}else{Bad "Sepidz=$sep"}
if($sma -eq '20260717.22'){Ok "Smart frozen=$sma"}else{Bad "Smart=$sma"}

$e=$null;$t=$null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\windows\connect-update.ps1'),[ref]$t,[ref]$e)
if($e -and $e.Count){Bad 'update parse'}else{Ok 'update parse'}
if(Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern 'Invoke-BundleDownloadfunction' -Quiet){Bad 'dup header'}else{Ok 'no dup header'}
if(-not (Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern 'attempt -le 3' -Quiet)){Bad 'retry3'}else{Ok 'retry3'}
if(Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'ControlMaster=auto' -Quiet){Bad 'mux'}else{Ok 'no mux'}
if(-not (Select-String -Path scripts\client\git-mode.ps1 -Pattern 'skip_duplicate' -Quiet)){Bad 'dedupe'}else{Ok 'dedupe'}

# remote update file parse-equivalent: grep function line
$cmd='grep -n "function Invoke-BundleDownload" /usr/local/share/claude-client/connect-update.ps1 | head -3'
$o=Join-Path $env:TEMP 'c21r.txt'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','sepidz@192.168.250.70',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e')
$null=$p.WaitForExit(12000)
$line=((Get-Content $o -Raw)+'').Trim()
Write-Host ("remote: "+$line)
if($line -match 'Invoke-BundleDownloadfunction'){Bad 'remote still broken'}elseif($line -match 'function Invoke-BundleDownload'){Ok 'remote update header clean'}else{Bad 'remote header missing'}

if($fail -eq 0){Write-Host 'ALL GOOD' -ForegroundColor Green}else{Write-Host "FAIL=$fail" -ForegroundColor Red; exit $fail}
