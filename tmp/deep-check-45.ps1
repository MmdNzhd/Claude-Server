$ErrorActionPreference='Continue'
$fail=0; $warn=0
function Ok($m){ Write-Host "  PASS  $m" }
function Bad($m){ Write-Host "  FAIL  $m"; $script:fail++ }
function Warn($m){ Write-Host "  WARN  $m"; $script:warn++ }
function Sec($t){ Write-Host "`n========== $t ==========" }

$day = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
$repo = 'D:\Smart\Claude-Code-Server\scripts\client'
$cc = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'

Sec '1) LATEST SESSION'
if (-not (Test-Path $day)) { Bad 'day log missing'; Write-Host "FAILS=$fail"; exit 1 }
$starts = @(Select-String -Path $day -Pattern 'session start v' | Select-Object -Last 5)
$starts | ForEach-Object { Write-Host ("         " + $_.Line.Substring(0,[Math]::Min(160,$_.Line.Length))) }
$lastStart = Select-String -Path $day -Pattern 'session start v(\d+\.\d+)' | Select-Object -Last 1
if (-not $lastStart) { Bad 'no session start' } else {
  $ver = $lastStart.Matches[0].Groups[1].Value
  $sid = if ($lastStart.Line -match '\[([a-f0-9]{12})\]') { $Matches[1] } else { '?' }
  if ($ver -eq '20260721.45') { Ok "latest session ver=$ver sid=$sid" } else { Bad "latest session ver=$ver (want 20260721.45) sid=$sid" }
  $script:sid = $sid
  $script:ver = $ver
}

Sec '2) NO MASS KILL IN LATEST SESSION'
$sid = $script:sid
$killProxy = @(Select-String -Path $day -Pattern "\[$sid\].*proxy_settings_changed" -EA SilentlyContinue)
$killAuth = @(Select-String -Path $day -Pattern "\[$sid\].*LAUNCH_KILL: reason=auth_relaunch" -EA SilentlyContinue)
$killSkip = @(Select-String -Path $day -Pattern "\[$sid\].*LAUNCH_KILL_SKIP|preserved_open_windows" -EA SilentlyContinue)
$killAny = @(Select-String -Path $day -Pattern "\[$sid\].*LAUNCH_KILL" -EA SilentlyContinue)
if ($killProxy.Count -eq 0) { Ok 'no proxy_settings_changed kill' } else { Bad ("proxy kill count=" + $killProxy.Count); $killProxy | Select-Object -Last 3 | %{ Write-Host ("         "+$_.Line.Substring(0,[Math]::Min(180,$_.Line.Length))) } }
if ($killAuth.Count -eq 0) { Ok 'no auth_relaunch kill' } else { Warn ("auth kill count=" + $killAuth.Count) }
if ($killSkip.Count -gt 0) { Ok ("preserve markers=" + $killSkip.Count); $killSkip | Select-Object -Last 5 | %{ Write-Host ("         "+$_.Line.Substring(0,[Math]::Min(180,$_.Line.Length))) } }
else { Warn 'no preserve log lines in this session (ok if proxy unchanged)' }
if ($killAny.Count -gt 0) {
  Warn ("other LAUNCH_KILL lines=" + $killAny.Count)
  $killAny | Select-Object -Last 5 | %{ Write-Host ("         "+$_.Line.Substring(0,[Math]::Min(180,$_.Line.Length))) }
} else { Ok 'zero LAUNCH_KILL in latest session' }

$recentKill = @(Select-String -Path $day -Pattern 'proxy_settings_changed soft-stop' -EA SilentlyContinue | Where-Object { $_.Line -match '\[2026-07-21 15:(4[5-9]|5[0-9])|\[2026-07-21 1[6-9]:|\[2026-07-21 2' })
if ($recentKill.Count -eq 0) { Ok 'no proxy soft-stop after 15:45' } else { Bad ("proxy soft-stop after 15:45 count="+$recentKill.Count) }

Sec '3) CODE ON DISK (.45 + no-kill)'
foreach ($pair in @(
  @('repo', "$repo\windows\connect-version.txt", "$repo\editor-launch.ps1"),
  @('Claude-Connect', "$cc\connect-version.txt", "$cc\editor-launch.ps1")
)) {
  $name,$vf,$elp = $pair
  $v = if (Test-Path $vf) { (Get-Content $vf -Raw).Trim() } else { 'MISSING' }
  if ($v -eq '20260721.45') { Ok "$name ver=$v" } else { Bad "$name ver=$v" }
  $hasPreserve = Select-String -Path $elp -Pattern 'preserved_open_windows' -Quiet
  $hasKill = Select-String -Path $elp -Pattern 'proxy_settings_changed' -Quiet
  $hasElev = Select-String -Path $elp -Pattern 'elevated_direct_fallback' -Quiet
  if ($hasPreserve -and -not $hasKill) { Ok "$name preserve=yes proxy_kill=no" } else { Bad "$name preserve=$hasPreserve proxy_kill=$hasKill" }
  if ($hasElev) { Ok "$name elevated_fallback=yes" } else { Warn "$name elevated_fallback missing" }
}

Sec '4) LIVE CURSOR WINDOWS'
$all = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -match 'Cursor' })
$mains = @($all | Where-Object { $_.CommandLine -match 'ClaudeServerCursorProfile' -and $_.CommandLine -notmatch '--type=' })
$personal = @($all | Where-Object { $_.CommandLine -match 'AppData\\Roaming\\Cursor' -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine -notmatch 'ClaudeServerCursorProfile' })
Ok ("Cursor.exe total=$($all.Count) server_mains=$($mains.Count) personal_mains=$($personal.Count)")
if ($mains.Count -ge 1) { Ok "server profile Cursor alive (mains=$($mains.Count))" } else { Bad 'no ClaudeServerCursorProfile main process' }
$cliPorts=@()
foreach ($p in $mains) {
  $c=[string]$p.CommandLine
  $hasP = $c -match '--proxy-server=socks5://127\.0\.0\.1:(1908\d)'
  $port = if ($hasP) { [int]$Matches[1] } else { $null }
  $hasH2 = $c -match '--disable-http2'
  if ($hasP) { $cliPorts += $port; Ok "main pid=$($p.ProcessId) proxy=:$port disableHttp2=$hasH2" }
  else { Warn "main pid=$($p.ProcessId) missing --proxy-server (may be old window)" }
}

Sec '5) TUNNELS + SOCKS'
$legacyD=0; $goodL=0
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.Name -eq 'ssh.exe' -and $_.CommandLine -match '-N' -and $_.CommandLine -match '-R\s+\d+:localhost:22' -and
  $_.CommandLine -match '\bclaude-server(\s|$)' -and $_.CommandLine -notmatch 'sepidz'
} | ForEach-Object {
  $cmd=[string]$_.CommandLine
  if ($cmd -match '-L\s+127\.0\.0\.1:(1908\d):127\.0\.0\.1:10808') { $goodL++; Ok "-L pid=$($_.ProcessId) socks=$($Matches[1])" }
  elseif ($cmd -match '-D\s+127\.0\.0\.1:1908') { $legacyD++; Bad "legacy -D pid=$($_.ProcessId)" }
}
if ($goodL -ge 1) { Ok "-L count=$goodL" } else { Bad 'no -L tunnel' }
if ($legacyD -eq 0) { Ok 'zero legacy -D' } else { Bad "legacy -D=$legacyD" }

$working=@()
foreach ($p in 19080..19089) {
  $listen=$false
  try { $listen=[bool](Test-NetConnection 127.0.0.1 -Port $p -WarningAction SilentlyContinue -InformationLevel Quiet -EA SilentlyContinue) } catch {}
  if (-not $listen) { continue }
  $ip = & curl.exe -sS --max-time 8 --socks5-hostname "127.0.0.1:$p" https://api.ipify.org 2>$null
  $code = & curl.exe -sS -o NUL -w '%{http_code}' --max-time 10 --socks5-hostname "127.0.0.1:$p" https://api2.cursor.sh/ 2>$null
  if ($ip -eq '89.58.16.104' -and $code -eq '200') { $working += $p; Ok "socks $p Austria+api2" }
  else { Bad "socks $p ip=$ip api2=$code" }
}

Sec '6) SETTINGS ALIGN'
$s = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
if (Test-Path $s) {
  $j = Get-Content $s -Raw | ConvertFrom-Json
  $proxy=[string]$j.'http.proxy'
  Ok "http.proxy=$proxy support=$($j.'http.proxySupport') disableHttp2=$($j.'cursor.general.disableHttp2') strictSSL=$($j.'http.proxyStrictSSL')"
  if ($proxy -match ':(\d+)$') {
    $sp=[int]$Matches[1]
    if ($working -contains $sp) { Ok "settings port $sp verified" } else { Warn "settings port $sp not in working set ($($working -join ','))" }
  }
} else { Bad 'settings.json missing' }

Sec '7) LATEST SESSION KEY EVENTS'
$sid = $script:sid
$patterns = 'STEP end|Opening Cursor|LAUNCH_OK|LAUNCH_FAIL|CURSOR_PROXY|ENSURE_TUNNEL|proxy_leg|bat_relaunch|Updated to|PROC_START_OK|elevated_direct'
$hits = @(Select-String -Path $day -Pattern "\[$sid\].*($patterns)" -EA SilentlyContinue | Select-Object -Last 40)
if ($hits.Count -eq 0) { Warn 'no key events for sid' }
else {
  Ok ("key events=" + $hits.Count)
  $hits | ForEach-Object {
    $line=$_.Line
    if ($line.Length -gt 200) { $line = $line.Substring(0,200) }
    Write-Host ("         " + $line)
  }
}
$openOk = @(Select-String -Path $day -Pattern "\[$sid\].*Opening Cursor ok|\[$sid\].*LAUNCH_OK" -EA SilentlyContinue)
if ($openOk.Count -ge 1) { Ok 'Cursor open succeeded in session' } else { Warn 'no Opening Cursor ok / LAUNCH_OK line (may have skipped already_on_folder)' }

Sec 'SUMMARY'
Write-Host "FAILS=$fail WARNS=$warn"
if ($fail -eq 0) { Write-Host 'DEEP_CHECK_ALL_PASSED'; exit 0 }
Write-Host 'DEEP_CHECK_FAILED'; exit 1
