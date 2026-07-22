$ErrorActionPreference='Continue'
$fail=0; $warn=0
function Ok($m){ Write-Host "PASS  $m" }
function Bad($m){ Write-Host "FAIL  $m"; $script:fail++ }
function Warn($m){ Write-Host "WARN  $m"; $script:warn++ }
function Sec($t){ Write-Host "`n==== $t ====" }

$repo='D:\Smart\Claude-Code-Server\scripts\client'
$cc=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$day=Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
$settings=Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'

Sec '1) VERSION TRUTH'
foreach($pair in @(@('repo',"$repo\windows\connect-version.txt"),@('Claude-Connect',"$cc\connect-version.txt"))){
  $name=$pair[0]; $path=$pair[1]
  $v=if(Test-Path $path){(Get-Content $path -Raw).Trim()}else{'MISSING'}
  if($v -eq '20260721.46'){ Ok ($name+'='+$v) } else { Bad ($name+'='+$v) }
}

Sec '2) SAFETY INVARIANTS'
foreach($pair in @(@('repo',"$repo\editor-launch.ps1"),@('Claude-Connect',"$cc\editor-launch.ps1"))){
  $name=$pair[0]; $el=$pair[1]
  $hasPreserve=Select-String -Path $el -Pattern 'preserved_open_windows' -Quiet
  $hasProxyKill=Select-String -Path $el -Pattern 'proxy_settings_changed' -Quiet
  $hasSkipSocks=Select-String -Path $el -Pattern 'skip_settings no_http_leg' -Quiet
  $hasHttpSettings=Select-String -Path $el -Pattern 'http://127.0.0.1:' -Quiet
  $hasSocksCli=Select-String -Path $el -Pattern '--proxy-server=socks5://' -Quiet
  $authGuard=Select-String -Path $el -Pattern 'auth_relaunch_preserve_open_windows' -Quiet
  $neLine=@(Select-String -Path $el -Pattern 'elevated_non_elevated_launcher Start=false' | Select-Object -First 1)
  if($hasPreserve -and -not $hasProxyKill){ Ok ($name+' preserve=yes proxy_softstop=no') } else { Bad ($name+' preserve/kill') }
  if($hasSkipSocks){ Ok ($name+' never write socks5 settings') } else { Bad ($name+' missing skip_settings') }
  if($hasHttpSettings){ Ok ($name+' settings http://') } else { Bad ($name+' missing http settings') }
  if($hasSocksCli){ Ok ($name+' CLI socks5 kept') } else { Bad ($name+' CLI socks5 missing') }
  if($authGuard){ Ok ($name+' auth multi-window guard') } else { Bad ($name+' auth guard missing') }
  if($neLine.Count -ge 1 -and $neLine[0].Line -match 'DEBUG'){ Ok ($name+' non_elevated=DEBUG') } else { Warn ($name+' non_elevated not DEBUG') }
}

Sec '3) TUNNEL CODE + PARSE'
foreach($pair in @(@('repo',"$repo\git-mode.ps1"),@('Claude-Connect',"$cc\git-mode.ps1"))){
  $name=$pair[0]; $gm=$pair[1]
  foreach($pat in @('Get-HttpProxyPort','XrayServerHttpPort','19180','10809','missing_http','Add-TunnelHttpProxyLeg','http_proxy_leg')){
    if(Select-String -Path $gm -Pattern $pat -Quiet){ Ok ($name+' has '+$pat) } else { Bad ($name+' missing '+$pat) }
  }
  $tokens=$null; $errs=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($gm,[ref]$tokens,[ref]$errs)
  if($errs.Count -eq 0){ Ok ($name+' git-mode PARSE_OK') } else { Bad ($name+' parse errs='+$errs.Count) }
}
$el="$repo\editor-launch.ps1"; $tokens=$null; $errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($el,[ref]$tokens,[ref]$errs)
if($errs.Count -eq 0){ Ok 'editor-launch PARSE_OK' } else { Bad ('editor-launch parse '+$errs.Count) }

Sec '4) LIVE SMART (read-only)'
$mains=@(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -match 'Cursor' -and $_.CommandLine -match 'ClaudeServerCursorProfile' -and $_.CommandLine -notmatch '--type=' })
Ok ('server Cursor mains alive='+$mains.Count+' (not killing)')
$socksL=0; $httpL=0; $legacyD=0
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.Name -eq 'ssh.exe' -and $_.CommandLine -match '-N' -and $_.CommandLine -match '-R\s+\d+:localhost:22' -and $_.CommandLine -match 'claude-server' -and $_.CommandLine -notmatch 'sepidz'
} | ForEach-Object {
  $cmd=[string]$_.CommandLine
  if($cmd -match '-L\s+127\.0\.0\.1:1908\d:127\.0\.0\.1:10808'){ $socksL++ }
  if($cmd -match '-L\s+127\.0\.0\.1:1918\d:127\.0\.0\.1:10809'){ $httpL++ }
  if($cmd -match '-D\s+127\.0\.0\.1:1908'){ $legacyD++ }
}
Ok ('live -L socks='+$socksL+' http='+$httpL+' legacyD='+$legacyD)
if($legacyD -eq 0){ Ok 'zero legacy -D' } else { Bad ('legacy -D='+$legacyD) }
if($httpL -eq 0){ Warn 'no HTTP -L yet (expected until each laptop reconnects on .46)' } else { Ok 'HTTP -L present' }

$socksOk=0
foreach($p in 19080..19089){
  try{ $listen=[bool](Test-NetConnection 127.0.0.1 -Port $p -WarningAction SilentlyContinue -InformationLevel Quiet -EA SilentlyContinue) } catch { $listen=$false }
  if(-not $listen){ continue }
  $ip=& curl.exe -sS --max-time 6 --socks5-hostname ("127.0.0.1:"+$p) https://api.ipify.org 2>$null
  if($ip -eq '89.58.16.104'){ $socksOk++; Ok ('socks '+$p+' Austria') } else { Warn ('socks '+$p+' ip='+$ip) }
}
Ok ('Austria socks working='+$socksOk)

$httpOk=0
foreach($p in 19180..19189){
  try{ $listen=[bool](Test-NetConnection 127.0.0.1 -Port $p -WarningAction SilentlyContinue -InformationLevel Quiet -EA SilentlyContinue) } catch { $listen=$false }
  if(-not $listen){ continue }
  $ip=& curl.exe -sS --max-time 6 -x ("http://127.0.0.1:"+$p) https://api.ipify.org 2>$null
  $c7=& curl.exe -sS -o NUL -w '%{http_code}' --max-time 8 -x ("http://127.0.0.1:"+$p) https://mcp.context7.com/mcp 2>$null
  if($ip -eq '89.58.16.104'){ $httpOk++; Ok ('http-proxy '+$p+' Austria context7='+$c7) } else { Bad ('http-proxy '+$p+' ip='+$ip) }
}
if($httpOk -eq 0){ Warn 'no local 1918x yet (need .46 reconnect)' } else { Ok ('HTTP forwards working='+$httpOk) }

if(Test-Path $settings){
  $j=Get-Content $settings -Raw | ConvertFrom-Json
  $proxy=[string]$j.'http.proxy'
  Ok ('current settings http.proxy='+$proxy)
  if($proxy -match '^socks5://'){ Warn 'settings still socks5 until this laptop reconnects on .46' }
  elseif($proxy -match '^http://127\.0\.0\.1:1918'){ Ok 'settings already http://1918x' }
}

Sec '5) LOG + HASH'
$recentSoft=@(Select-String -Path $day -Pattern 'LAUNCH_KILL: reason=proxy_settings_changed' -EA SilentlyContinue)
if($recentSoft.Count -eq 0){ Ok 'laptop daylog has zero proxy_settings_changed kills' } else { Warn ('proxy kill lines still in daylog count='+$recentSoft.Count) }
$pres=@(Select-String -Path $day -Pattern 'preserved_open_windows' -EA SilentlyContinue | Select-Object -Last 3)
Ok ('preserved_open_windows hits='+$pres.Count)
foreach($name in @('editor-launch.ps1','git-mode.ps1','connect.ps1','connect-version.txt')){
  $aPath= if($name -match '^connect'){ Join-Path $repo ("windows\"+$name) } else { Join-Path $repo $name }
  $bPath=Join-Path $cc $name
  if(-not (Test-Path $aPath) -or -not (Test-Path $bPath)){ Bad ('missing hash file '+$name); continue }
  $a=(Get-FileHash $aPath -Algorithm SHA256).Hash
  $b=(Get-FileHash $bPath -Algorithm SHA256).Hash
  if($a -eq $b){ Ok ('hash match '+$name) } else { Bad ('hash MISMATCH '+$name) }
}

Sec 'SUMMARY'
Write-Host ('FAILS='+$fail+' WARNS='+$warn)
if($fail -eq 0){ Write-Host 'FLEET_SURE_PASSED'; exit 0 }
Write-Host 'FLEET_SURE_FAILED'; exit 1
