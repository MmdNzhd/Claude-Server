$ErrorActionPreference='Continue'
$fail=0; $warn=0
function Ok($m){ Write-Host "PASS  $m" }
function Bad($m){ Write-Host "FAIL  $m"; $script:fail++ }
function Warn($m){ Write-Host "WARN  $m"; $script:warn++ }
function Sec($t){ Write-Host "`n==== $t ====" }

$day = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
$cc = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$repo = 'D:\Smart\Claude-Code-Server\scripts\client'
$settings = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
$mcp = Join-Path $env:USERPROFILE '.cursor\mcp.json'
# also profile mcp if any
$profileMcp = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\globalStorage\cursor.mcp\mcp.json'

Sec 'A) VERSIONS ALIGNED'
foreach ($p in @(
  @('repo', "$repo\windows\connect-version.txt"),
  @('Claude-Connect', "$cc\connect-version.txt")
)) {
  $v = if (Test-Path $p[1]) { (Get-Content $p[1] -Raw).Trim() } else { 'MISSING' }
  if ($v -eq '20260721.45') { Ok "$($p[0])=$v" } else { Bad "$($p[0])=$v" }
}
$el = "$cc\editor-launch.ps1"
$hasPreserve = Select-String -Path $el -Pattern 'preserved_open_windows' -Quiet
$hasKill = Select-String -Path $el -Pattern 'proxy_settings_changed' -Quiet
$hasAuthGuard = Select-String -Path $el -Pattern 'auth_relaunch_preserve_open_windows|main_window_count' -Quiet
if ($hasPreserve -and -not $hasKill) { Ok 'Claude-Connect: preserve=yes proxy_softstop_string=no' } else { Bad "preserve=$hasPreserve killstr=$hasKill" }
if ($hasAuthGuard) { Ok 'Claude-Connect: auth multi-window guard present' } else { Warn 'auth multi-window guard pattern not found (check alternate naming)' }

Sec 'B) POST-.45 KILL PROOF (after 15:45)'
$post = @(Select-String -Path $day -Pattern 'proxy_settings_changed soft-stop' | Where-Object { $_.Line -match '\[2026-07-21 15:(4[5-9]|5[0-9])|\[2026-07-21 1[6-9]' })
$pre = @(Select-String -Path $day -Pattern 'proxy_settings_changed soft-stop' | Where-Object { $_.Line -match '\[2026-07-21 15:(3[0-9]|4[0-4])' })
Ok ("pre-15:45 soft-stop count=" + $pre.Count)
if ($post.Count -eq 0) { Ok 'post-15:45 soft-stop count=0' } else { Bad ("post-15:45 soft-stop="+$post.Count); $post | %{ Write-Host $_.Line } }
$preserve = @(Select-String -Path $day -Pattern 'preserved_open_windows' | Where-Object { $_.Line -match '\[2026-07-21 15:(4[5-9]|5[0-9])' })
if ($preserve.Count -ge 1) { Ok ("preserved_open_windows hits="+$preserve.Count); $preserve | Select-Object -Last 3 | %{ Write-Host ("  "+$_.Line) } } else { Bad 'no preserved_open_windows after 15:45' }

Sec 'C) LATEST SESSION HARD FACTS'
$last = Select-String -Path $day -Pattern 'session start v(\d+\.\d+)' | Select-Object -Last 1
$ver = $last.Matches[0].Groups[1].Value
$sid = if ($last.Line -match '\[([a-f0-9]{12})\]') { $Matches[1] } else { '?' }
if ($ver -eq '20260721.45') { Ok "latest ver=$ver sid=$sid" } else { Bad "latest ver=$ver" }
$sidLines = @(Select-String -Path $day -Pattern "\[$sid\]")
$kills = @($sidLines | Where-Object { $_.Line -match 'LAUNCH_KILL: reason=' })
$openOk = @($sidLines | Where-Object { $_.Line -match 'Opening Cursor ok' })
$openFail = @($sidLines | Where-Object { $_.Line -match 'Opening Cursor fail|LAUNCH_FAIL' })
$proxyPreserve = @($sidLines | Where-Object { $_.Line -match 'preserved_open_windows' })
$proxySoft = @($sidLines | Where-Object { $_.Line -match 'proxy_settings_changed soft-stop' })
$taskOk = @($sidLines | Where-Object { $_.Line -match 'PROC_START_OK: mode=elevated_launch_task' })
$neFail = @($sidLines | Where-Object { $_.Line -match 'elevated_non_elevated_launcher' })
Ok ("sid lines="+$sidLines.Count)
if ($kills.Count -eq 0) { Ok 'latest: zero LAUNCH_KILL reason' } else { Bad ("latest kills="+$kills.Count) }
if ($proxySoft.Count -eq 0) { Ok 'latest: zero proxy soft-stop' } else { Bad 'latest has proxy soft-stop' }
if ($proxyPreserve.Count -ge 1) { Ok 'latest: preserved_open_windows logged' } else { Warn 'latest: no preserve line' }
if ($openOk.Count -ge 1) { Ok ("latest: Opening Cursor ok x"+$openOk.Count) } else { Bad 'latest: no Opening Cursor ok' }
if ($openFail.Count -eq 0) { Ok 'latest: no Opening Cursor fail' } else { Bad ("latest open fails="+$openFail.Count) }
if ($taskOk.Count -ge 1) { Ok 'latest: elevated_launch_task OK' } else { Warn 'latest: no elevated_launch_task OK' }
if ($neFail.Count -ge 1) { Warn ("latest: elevated_non_elevated_launcher fail x"+$neFail.Count+" (fallback path; launch still OK if taskOk)") }

Sec 'D) LIVE PROCESSES / SOCKS / SETTINGS'
$all = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -match 'Cursor' })
$mains = @($all | Where-Object { $_.CommandLine -match 'ClaudeServerCursorProfile' -and $_.CommandLine -notmatch '--type=' })
if ($mains.Count -ge 1) { Ok ("server mains="+$mains.Count) } else { Bad 'no server Cursor main' }
foreach ($p in $mains) {
  $c=[string]$p.CommandLine
  $port = if ($c -match '--proxy-server=socks5://127\.0\.0\.1:(\d+)') { $Matches[1] } else { 'NONE' }
  $h2 = $c -match '--disable-http2'
  Ok ("main pid=$($p.ProcessId) cli_proxy=$port disableHttp2=$h2")
}
$legacyD=@(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -eq 'ssh.exe' -and $_.CommandLine -match '-D\s+127\.0\.0\.1:1908' -and $_.CommandLine -match 'claude-server' -and $_.CommandLine -notmatch 'sepidz' })
$goodL=@(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -eq 'ssh.exe' -and $_.CommandLine -match '-L\s+127\.0\.0\.1:1908\d:127\.0\.0\.1:10808' -and $_.CommandLine -match 'claude-server' -and $_.CommandLine -notmatch 'sepidz' })
if ($legacyD.Count -eq 0) { Ok 'zero legacy -D' } else { Bad ("legacy -D="+$legacyD.Count) }
Ok ("-L tunnels="+$goodL.Count)

$j = Get-Content $settings -Raw | ConvertFrom-Json
$proxy = [string]$j.'http.proxy'
Ok ("settings proxy=$proxy support=$($j.'http.proxySupport') disableHttp2=$($j.'cursor.general.disableHttp2')" )
if ($proxy -match 'socks5://127\.0\.0\.1:(1908\d)') {
  $sp=[int]$Matches[1]
  $ip = & curl.exe -sS --max-time 8 --socks5-hostname "127.0.0.1:$sp" https://api.ipify.org 2>$null
  $code = & curl.exe -sS -o NUL -w '%{http_code}' --max-time 10 --socks5-hostname "127.0.0.1:$sp" https://api2.cursor.sh/ 2>$null
  if ($ip -eq '89.58.16.104' -and $code -eq '200') { Ok "settings socks $sp Austria+api2 OK" } else { Bad "settings socks $sp ip=$ip api2=$code" }
} else { Bad "settings proxy unexpected: $proxy" }

Sec 'E) MCP CONFIG (root cause of Invalid URL?)'
foreach ($mp in @(@('user_home', $mcp), @('profile_guess', $profileMcp))) {
  Write-Host ("-- mcp file: $($mp[0]) path=$($mp[1]) exists=$(Test-Path $mp[1])")
  if (-not (Test-Path $mp[1])) { continue }
  $raw = Get-Content $mp[1] -Raw
  Write-Host ("   size=$($raw.Length)")
  try {
    $m = $raw | ConvertFrom-Json
    $servers = $m.mcpServers
    if (-not $servers) { $servers = $m.servers }
    if (-not $servers) { Warn "$($mp[0]): no mcpServers key"; Write-Host ($raw.Substring(0,[Math]::Min(400,$raw.Length))); continue }
    foreach ($name in @('figma','context7','user-figma','user-context7','plugin-figma-figma')) {
      $prop = $servers.PSObject.Properties | Where-Object { $_.Name -eq $name -or $_.Name -like "*$name*" } | Select-Object -First 1
      if (-not $prop) { continue }
      $s = $prop.Value
      $url = $null
      if ($s.url) { $url = [string]$s.url }
      elseif ($s.serverUrl) { $url = [string]$s.serverUrl }
      $cmd = if ($s.command) { [string]$s.command } else { '' }
      $hdr = ''
      if ($s.headers) { $hdr = ($s.headers | ConvertTo-Json -Compress) }
      Write-Host ("   SERVER name=$($prop.Name) url=[$url] command=[$cmd] headers=$hdr")
      if ($url) {
        if ($url -match '^https?://') { Ok "$($prop.Name) url scheme OK" }
        elseif ($url -match '^socks') { Bad "$($prop.Name) url is socks (proxy leak?): $url" }
        else { Bad "$($prop.Name) url bad scheme: $url" }
      }
    }
    # dump all server names + url/command briefly
    foreach ($prop in $servers.PSObject.Properties) {
      $s=$prop.Value
      $u= if ($s.url) { [string]$s.url } elseif ($s.serverUrl) { [string]$s.serverUrl } else { '' }
      $c= if ($s.command) { [string]$s.command } else { '' }
      Write-Host ("   ALL $($prop.Name) url=[$u] cmd=[$c]")
    }
  } catch { Bad ("mcp parse fail $($mp[0]): $($_.Exception.Message)") }
}

# Also check if Cursor settings somehow put proxy into mcp
$cursorMcpInSettings = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
# search mcp.json under profile
Get-ChildItem (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile') -Recurse -Filter 'mcp.json' -EA SilentlyContinue |
  Select-Object -First 10 | ForEach-Object { Write-Host ("FOUND_MCP " + $_.FullName + " size=" + $_.Length) }

Sec 'F) AUTH STALE - latest evidence'
$auth = @(Select-String -Path $day -Pattern 'golden_stale|AUTH ERROR|AUTH_DECISION|Syncing Cursor auth' | Select-Object -Last 15)
$auth | ForEach-Object { Write-Host $_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)) }
$latestAuth = @($sidLines | Where-Object { $_.Line -match 'Syncing Cursor auth|golden_stale|AUTH' })
if (@($latestAuth | Where-Object { $_.Line -match 'golden_stale|AUTH ERROR' }).Count -eq 0) {
  Ok 'latest session: no golden_stale/AUTH ERROR'
} else { Bad 'latest session still golden_stale' }
$skip = @($latestAuth | Where-Object { $_.Line -match 'skipped \(stamp current\)' })
if ($skip.Count -ge 1) { Ok 'latest auth sync skipped stamp current' }

Sec 'G) FALLBACK PATH CERTAINTY'
# Prove every elevated_non_elevated_launcher fail in last 30m was followed by task OK before Opening Cursor ok
$since = (Get-Date).AddMinutes(-40)
function Parse-Ts([string]$line) {
  if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]') {
    try { return [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null) } catch { return $null }
  }
  return $null
}
$ne = @(Select-String -Path $day -Pattern 'PROC_START_FAIL: mode=elevated_non_elevated_launcher' | Where-Object { (Parse-Ts $_.Line) -ge $since })
$recovered=0; $unrecovered=0
foreach ($hit in $ne) {
  $ts = Parse-Ts $hit.Line
  $sid2 = if ($hit.Line -match '\[([a-f0-9]{12})\]') { $Matches[1] } else { '' }
  $after = @(Select-String -Path $day -Pattern "\[$sid2\].*(PROC_START_OK: mode=elevated_launch_task|Opening Cursor ok|Opening Cursor fail|LAUNCH_FAIL)" | Where-Object {
    $t2 = Parse-Ts $_.Line; $t2 -and $t2 -ge $ts -and $t2 -le $ts.AddSeconds(30)
  })
  $okTask = @($after | Where-Object { $_.Line -match 'elevated_launch_task|Opening Cursor ok' })
  $badOpen = @($after | Where-Object { $_.Line -match 'Opening Cursor fail|LAUNCH_FAIL' })
  if ($okTask.Count -ge 1 -and $badOpen.Count -eq 0) { $recovered++ } else { $unrecovered++; Write-Host ("UNRECOVERED near "+$hit.Line) }
}
Ok ("non_elevated_fail last40m=$($ne.Count) recovered=$recovered unrecovered=$unrecovered")
if ($unrecovered -gt 0) { Bad 'some launcher fails did not recover' } else { Ok 'all non_elevated fails recovered via task' }

Sec 'SUMMARY'
Write-Host "FAILS=$fail WARNS=$warn"
if ($fail -eq 0) { Write-Host 'SURE_VERIFY_PASSED' } else { Write-Host 'SURE_VERIFY_FAILED' }
exit $fail
