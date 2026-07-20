$ErrorActionPreference='Continue'
$fail=0; $warn=0
function Ok($m){ Write-Host ("OK   " + $m) -ForegroundColor Green }
function Bad($m){ Write-Host ("BAD  " + $m) -ForegroundColor Red; $script:fail++ }
function Warn($m){ Write-Host ("WARN " + $m) -ForegroundColor Yellow; $script:warn++ }
function Info($m){ Write-Host ("     " + $m) -ForegroundColor DarkGray }

$expect='20260719.21'
$pkgRoot = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260719\claude-code'
$pkgWin = Join-Path $pkgRoot 'windows'

Write-Host "`n########## A) VERSION TRIANGLE ##########" -ForegroundColor Cyan
$srcVer=(Get-Content 'scripts\client\windows\connect-version.txt' -Raw).Trim()
$psVer=([regex]::Match((Get-Content 'scripts\client\windows\connect.ps1' -Raw),"ConnectVersion = '([^']+)'")).Groups[1].Value
$pkgVer=(Get-Content (Join-Path $pkgWin 'connect-version.txt') -Raw).Trim()
$macSrc=(Get-Content 'scripts\client\mac\connect-version.txt' -Raw -EA SilentlyContinue).Trim()
function RemoteVer([string]$t){
  $o=Join-Path $env:TEMP ('dv-'+(Get-Random)+'.txt')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',$t,"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e')
  if(-not $p.WaitForExit(15000)){ try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -EA SilentlyContinue)+'').Trim()
}
$sep=RemoteVer 'sepidz@192.168.250.70'
$sma=RemoteVer 'smart@192.168.210.240'
Info "src=$srcVer connect.ps1=$psVer mac=$macSrc pkg=$pkgVer sepidz=$sep smart=$sma"
if($srcVer -eq $expect -and $psVer -eq $expect -and $pkgVer -eq $expect -and $sep -eq $expect){ Ok "Sepidz triangle = $expect" } else { Bad "version drift" }
if($sma -eq '20260717.22'){ Ok 'Smart frozen .22' } else { Bad "Smart=$sma" }
if($macSrc -eq $expect){ Ok 'mac version synced' } else { Warn "mac version=$macSrc" }

Write-Host "`n########## B) FULL PARSE (all shipped client scripts) ##########" -ForegroundColor Cyan
$parseFiles=@(
  'scripts\client\windows\connect.ps1',
  'scripts\client\windows\connect-update.ps1',
  'scripts\client\connect-ui.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\editor-launch.ps1',
  'scripts\client\cursor-auth-laptop.ps1',
  'scripts\client\connect-diagnostic.ps1'
)
foreach($f in $parseFiles){
  $e=$null;$tok=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f),[ref]$tok,[ref]$e)
  if($e -and $e.Count){ Bad ("PARSE $f :: "+$e[0].ToString()) }
  else { Ok ("PARSE $f") }
}
# package copies too
foreach($name in @('connect.ps1','connect-update.ps1','connect-ui.ps1','git-mode.ps1')){
  $f=Join-Path $pkgWin $name
  $e=$null;$tok=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tok,[ref]$e)
  if($e -and $e.Count){ Bad ("PARSE pkg/$name :: "+$e[0].ToString()) }
  else { Ok ("PARSE pkg/$name") }
}

Write-Host "`n########## C) SHA: source vs package (unpatched files) ##########" -ForegroundColor Cyan
$shaPairs=@(
  @('scripts\client\connect-ui.ps1','windows\connect-ui.ps1'),
  @('scripts\client\git-mode.ps1','windows\git-mode.ps1'),
  @('scripts\client\windows\connect.bat','windows\connect.bat'),
  @('scripts\client\windows\connect-update.ps1','windows\connect-update.ps1'),
  @('scripts\client\editor-launch.ps1','windows\editor-launch.ps1'),
  @('scripts\client\connect-ui.sh','mac\connect-ui.sh'),
  @('scripts\client\git-mode.sh','mac\git-mode.sh')
)
foreach($pr in $shaPairs){
  $a=(Get-FileHash $pr[0] -Algorithm SHA256).Hash
  $b=(Get-FileHash (Join-Path $pkgRoot $pr[1]) -Algorithm SHA256).Hash
  if($a -eq $b){ Ok ("SHA $($pr[1])") } else { Bad ("SHA DIFF $($pr[1])") }
}
# connect.ps1 must differ (IP patch) but markers
$cp=Get-Content (Join-Path $pkgWin 'connect.ps1') -Raw
if($cp -match 'claude-server-sepidz' -and $cp -match '192\.168\.250\.70' -and $cp -notmatch '192\.168\.210\.240'){ Ok 'connect.ps1 IP/alias patch' }
else { Bad 'connect.ps1 patch wrong' }
if($cp -match "ConnectVersion = '$expect'"){ Ok 'pkg ConnectVersion' } else { Bad 'pkg ConnectVersion' }

Write-Host "`n########## D) REMOTE FILE BYTE-COMPARE (scp critical files) ##########" -ForegroundColor Cyan
$tmpdir=Join-Path $env:TEMP ('deep-remote-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmpdir | Out-Null
$remoteFiles=@('connect-version.txt','connect-update.ps1','git-mode.ps1','connect-ui.ps1','connect.ps1','connect.bat')
foreach($rf in $remoteFiles){
  $local=Join-Path $tmpdir $rf
  $p=Start-Process scp -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-q',"sepidz@192.168.250.70:/usr/local/share/claude-client/$rf",$local) -NoNewWindow -PassThru -RedirectStandardOutput ($local+'.o') -RedirectStandardError ($local+'.e')
  if(-not $p.WaitForExit(30000) -or $p.ExitCode -ne 0 -or -not (Test-Path $local)){ Bad "scp $rf failed"; continue }
  $pkgFile=Join-Path $pkgWin $rf
  if(-not (Test-Path $pkgFile)){ Bad "pkg missing $rf"; continue }
  $h1=(Get-FileHash $pkgFile -Algorithm SHA256).Hash
  $h2=(Get-FileHash $local -Algorithm SHA256).Hash
  if($h1 -eq $h2){ Ok "remote==package $rf" }
  else {
    # connect.ps1 on server IS the sepidz-patched one from package - should match package
    Bad "remote!=package $rf"
    Info ("pkg=$($h1.Substring(0,12)) rem=$($h2.Substring(0,12))")
  }
}

Write-Host "`n########## E) STRUCTURAL SANITY (no corruption patterns) ##########" -ForegroundColor Cyan
$corruptPatterns=@(
  @{f='scripts\client\windows\connect-update.ps1'; p='Invoke-BundleDownloadfunction'; n='dup BundleDownload'},
  @{f='scripts\client\windows\connect.ps1'; p='ControlMaster=auto'; n='broken mux'},
  @{f='scripts\client\git-mode.ps1'; p="SshX @'"; n='broken here-string SshX'},
  @{f='scripts\client\connect-ui.ps1'; p='Stop-ConnectSshMux'; n='leftover mux cleanup'},
  @{f=(Join-Path $pkgWin 'connect-update.ps1'); p='Invoke-BundleDownloadfunction'; n='pkg dup BundleDownload'},
  @{f=(Join-Path $tmpdir 'connect-update.ps1'); p='Invoke-BundleDownloadfunction'; n='remote dup BundleDownload'}
)
foreach($c in $corruptPatterns){
  if(-not (Test-Path $c.f)){ Warn ("skip missing "+$c.f); continue }
  $hit=Select-String -Path $c.f -Pattern $c.p -SimpleMatch -Quiet
  if($hit){ Bad ("FOUND corrupt: "+$c.n) } else { Ok ("absent: "+$c.n) }
}

Write-Host "`n########## F) BEHAVIOR CONTRACTS (code presence + shape) ##########" -ForegroundColor Cyan
# Update: 3 retries, 20s, fallback still exists
$upd=Get-Content 'scripts\client\windows\connect-update.ps1' -Raw
if($upd -match '(?s)for \(\$attempt = 1; \$attempt -le 3; \$attempt\+\+\)'){ Ok 'update for-attempt 1..3' } else { Bad 'update retry loop shape' }
if($upd -match 'TimeoutMs 20000 -RequireStdout'){ Ok 'update cat timeout 20s' } else { Bad 'update timeout' }
if($upd -match 'Resolve-UpdateEndpoint' -and $upd -match 'fallback'){ Ok 'update fallback path' } else { Bad 'update fallback' }
# count Invoke-SshCat definitions
$catDefs=([regex]::Matches($upd,'function Invoke-SshCat')).Count
if($catDefs -eq 1){ Ok 'single Invoke-SshCat' } else { Bad "Invoke-SshCat defs=$catDefs" }
$dlDefs=([regex]::Matches($upd,'function Invoke-BundleDownload')).Count
if($dlDefs -eq 1){ Ok 'single Invoke-BundleDownload' } else { Bad "BundleDownload defs=$dlDefs" }

# Push: one SSH + dedupe
$gm=Get-Content 'scripts\client\git-mode.ps1' -Raw
if($gm -match 'skip_duplicate' -and $gm -match 'LastPushConfKey'){ Ok 'push dedupe vars' } else { Bad 'push dedupe' }
if($gm -match 'claude-self-heal' -and $gm -match 'ACTIVE_MOUNT' -and $gm -match 'printf "LAPTOP_USER'){ Ok 'push combined remote script' } else { Bad 'push combined script' }
# Warn foreign: one probe cmd
if($gm -match 'printf "LU=%s\\nOS=%s\\nPORT=%s\\n"'){ Ok 'warn-foreign batched probe' } else { Bad 'warn-foreign batch' }
# Count SshX in Warn-ForeignServerSession body - should be fewer
$warnFn=[regex]::Match($gm,'(?s)function Warn-ForeignServerSession \{.*?^function Push-ServerConnectConf', [Text.RegularExpressions.RegexOptions]::Multiline).Value
$sshInWarn=([regex]::Matches($warnFn,'SshX ')).Count
Info "SshX calls inside Warn-ForeignServerSession path text=$sshInWarn (common case uses 1)"
if($sshInWarn -le 3){ Ok "warn SshX count<=3 ($sshInWarn)" } else { Warn "warn still many SshX=$sshInWarn" }

# Logging contracts
$ui=Get-Content 'scripts\client\connect-ui.ps1' -Raw
foreach($need in @('LastConnectLogSyncOk','Enter-ConnectSingleInstance','Invoke-ConnectLogProcTimed','Get-ConnectLogDayPath','512KB','FileShare.ReadWrite')){
  if($ui.Contains($need) -or $ui -match [regex]::Escape($need)){ Ok "log:$need" } else { Bad "missing log:$need" }
}

# connect.bat run id
$bat=Get-Content 'scripts\client\windows\connect.bat' -Raw
if($bat -match 'CLAUDE_CONNECT_RUN_ID'){ Ok 'bat RUN_ID' } else { Bad 'bat RUN_ID' }
if($ui -match 'CLAUDE_CONNECT_RUN_ID'){ Ok 'ui reuses RUN_ID as session' } else { Bad 'ui RUN_ID' }

Write-Host "`n########## G) DOT-SOURCE SMOKE (no full connect) ##########" -ForegroundColor Cyan
try {
  . .\scripts\client\connect-ui.ps1
  . .\scripts\client\git-mode.ps1
  foreach($fn in @('Enter-ConnectSingleInstance','Sync-ConnectLogToServer','Invoke-ConnectLogProcTimed','Push-ServerConnectConf','Warn-ForeignServerSession','Get-GitMode')){
    if(Get-Command $fn -EA SilentlyContinue){ Ok "cmd $fn" } else { Bad "missing cmd $fn" }
  }
} catch {
  Bad ("dot-source: "+$_.Exception.Message)
}

# connect-update: dot-source unsafe (exits). Instead AST-check + tokenize Invoke-SshCat body
try {
  $ast=$null;$tok=$null;$err=$null
  $ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\windows\connect-update.ps1'),[ref]$tok,[ref]$err)
  $funcs=@($ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | ForEach-Object { $_.Name })
  foreach($need in @('Invoke-SshTimed','Invoke-SshCat','Invoke-BundleDownload','Resolve-UpdateEndpoint','Write-UpdateFileLog')){
    if($funcs -contains $need){ Ok "update-fn $need" } else { Bad "update-fn missing $need" }
  }
  $dup=@($funcs | Group-Object | Where-Object { $_.Count -gt 1 })
  if($dup.Count -eq 0){ Ok 'update no duplicate function names' } else { Bad ("update dup funcs: "+($dup.Name -join ',')) }
} catch { Bad ("update AST: "+$_.Exception.Message) }

Write-Host "`n########## H) LIVE PROCESS / FOLDER SAFETY ##########" -ForegroundColor Cyan
$procs=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'connect(-update)?\.ps1' })
if($procs.Count -eq 0){ Ok 'no connect processes' }
else {
  foreach($pr in $procs){
    $cl=$pr.CommandLine; if($cl.Length -gt 180){$cl=$cl.Substring(0,180)}
    if($cl -match 'claude-code-client'){ Bad "Smart client running: $cl" }
    else { Warn "connect running: $cl" }
  }
}
$oldSep=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\connect-version.txt'
if(Test-Path $oldSep){
  $ov=(Get-Content $oldSep -Raw).Trim()
  Info "old folder sepidz-20260717 ver=$ov (auto-updates on next bat)"
  if($ov -eq $expect){ Ok 'old launch folder already .21' } else { Warn "old launch folder still $ov until next connect.bat" }
}

Write-Host "`n########## I) QUICK SSH HEALTH (Sepidz account) ##########" -ForegroundColor Cyan
$sw=[Diagnostics.Stopwatch]::StartNew()
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','claude-server-sepidz','echo OK; test -f /usr/local/share/claude-client/connect-update.ps1 && echo BUNDLE_OK') -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+'\hl.out') -RedirectStandardError ($env:TEMP+'\hl.err')
if(-not $p.WaitForExit(15000)){ Bad 'ssh health timeout' }
else {
  $sw.Stop()
  $out=((Get-Content ($env:TEMP+'\hl.out') -Raw)+'').Trim()
  Info ("ssh_ms=$($sw.ElapsedMilliseconds) out=$out")
  if($out -match 'OK' -and $out -match 'BUNDLE_OK'){ Ok 'ssh + bundle reachable' } else { Bad "ssh health out=$out" }
}

Write-Host "`n########## SUMMARY ##########" -ForegroundColor Cyan
if($fail -eq 0){
  Write-Host ("DEEP CHECK PASSED (warns=$warn)") -ForegroundColor Green
} else {
  Write-Host ("DEEP CHECK FAILED failures=$fail warns=$warn") -ForegroundColor Red
}
exit $fail
