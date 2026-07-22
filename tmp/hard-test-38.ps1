$ErrorActionPreference = 'Continue'
$fail = 0
$warn = 0
function Ok($m)  { Write-Host ("  PASS  " + $m) }
function Bad($m) { Write-Host ("  FAIL  " + $m); $script:fail++ }
function Warn($m){ Write-Host ("  WARN  " + $m); $script:warn++ }
function Sec($t) { Write-Host ("`n========== " + $t + " ==========") }

$repo = 'D:\Smart\Claude-Code-Server\scripts\client'
$cc   = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$day  = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
$bundleNote = Join-Path $env:TEMP 'bundle-ver-38test.txt'

Sec '1) VERSIONS + .38 CODE MARKERS'
$targets = @(
  @{ N='repo'; Vf="$repo\windows\connect-version.txt"; Cp="$repo\windows\connect.ps1"; Gm="$repo\git-mode.ps1"; El="$repo\editor-launch.ps1"; MacGm="$repo\git-mode.sh"; MacEl="$repo\editor-launch.sh"; MacV="$repo\mac\connect-version.txt"; MacC="$repo\mac\connect.sh" },
  @{ N='Claude-Connect'; Vf="$cc\connect-version.txt"; Cp="$cc\connect.ps1"; Gm="$cc\git-mode.ps1"; El="$cc\editor-launch.ps1"; MacGm="$cc\mac\git-mode.sh"; MacEl="$cc\mac\editor-launch.sh"; MacV="$cc\mac\connect-version.txt"; MacC="$cc\mac\connect.sh" }
)
foreach ($t in $targets) {
  $ver = if (Test-Path $t.Vf) { (Get-Content $t.Vf -Raw).Trim() } else { 'MISSING' }
  $cv = '?'
  if (Test-Path $t.Cp) {
    $m = Select-String -Path $t.Cp -Pattern "ConnectVersion = '([^']+)'" | Select-Object -First 1
    if ($m) { $cv = $m.Matches[0].Groups[1].Value }
  }
  $macVer = if (Test-Path $t.MacV) { (Get-Content $t.MacV -Raw).Trim() } else { 'MISSING' }
  $macCv = '?'
  if (Test-Path $t.MacC) {
    $m2 = Select-String -Path $t.MacC -Pattern "CONNECT_VERSION='([^']+)'" | Select-Object -First 1
    if ($m2) { $macCv = $m2.Matches[0].Groups[1].Value }
  }
  $okVer = ($ver -eq '20260721.38' -and $cv -eq '20260721.38' -and $macVer -eq '20260721.38' -and $macCv -eq '20260721.38')
  if ($okVer) { Ok ("{0}: versions win={1}/{2} mac={3}/{4}" -f $t.N,$ver,$cv,$macVer,$macCv) }
  else { Bad ("{0}: versions win={1}/{2} mac={3}/{4}" -f $t.N,$ver,$cv,$macVer,$macCv) }

  $need = @(
    @{ K='reseed'; F=$t.Gm; P='Test-TunnelNeedsProxyReseed'; Want=$true },
    @{ K='scoped'; F=$t.Gm; P='Never mass-kill'; Want=$true },
    @{ K='proxyArgs'; F=$t.El; P='Get-CursorProxyLaunchArgs'; Want=$true },
    @{ K='relaunch'; F=$t.El; P='proxy_settings_changed'; Want=$true },
    @{ K='strictFalse'; F=$t.El; P='proxyStrictSSL.; Value = \$false'; Want=$true },
    @{ K='noPreserve'; F=$t.El; P='preserved_open_windows'; Want=$false },
    @{ K='noAlignFn'; F=$t.El; P='Get-RunningCursorProxySocksPort'; Want=$false },
    @{ K='noAlignLog'; F=$t.El; P='CURSOR_PROXY_ALIGN'; Want=$false },
    @{ K='noAuthPreserve'; F=$t.El; P='auth_relaunch_preserve_open_windows'; Want=$false },
    @{ K='noListenDown'; F=$t.Gm; P='listen_down'; Want=$false },
    @{ K='macReseed'; F=$t.MacGm; P='tunnel_needs_proxy_reseed'; Want=$true },
    @{ K='macScoped'; F=$t.MacGm; P='Free OUR socks port only'; Want=$true },
    @{ K='macRelaunch'; F=$t.MacEl; P='proxy_settings_changed'; Want=$true },
    @{ K='macNoPreserve'; F=$t.MacEl; P='preserved_open_windows'; Want=$false },
    @{ K='macNoAlign'; F=$t.MacEl; P='running_cursor_proxy_socks_port|CURSOR_PROXY_ALIGN'; Want=$false },
    @{ K='macNoListenDown'; F=$t.MacGm; P='listen_down'; Want=$false },
    @{ K='proxyLegL'; F=$t.Gm; P='XrayServerSocksPort|proxy_leg=-L'; Want=$true }
  )
  foreach ($n in $need) {
    if (-not (Test-Path $n.F)) { Bad ("{0}: missing file for {1}" -f $t.N,$n.K); continue }
    $hit = [bool](Select-String -Path $n.F -Pattern $n.P -Quiet)
    if ($hit -eq $n.Want) { Ok ("{0}.{1}={2}" -f $t.N,$n.K,$hit) }
    else { Bad ("{0}.{1} hit={2} want={3}" -f $t.N,$n.K,$hit,$n.Want) }
  }
  $gmTxt = Get-Content $t.Gm -Raw
  if ($gmTxt -match "if \(\`$state -eq 'unknown'\) \{ return \`$false \}") { Ok ("{0}: unknown->no-reseed" -f $t.N) }
  else { Bad ("{0}: missing unknown early-return" -f $t.N) }
  $shTxt = Get-Content $t.MacGm -Raw
  if ($shTxt -match 'ok\|unknown\) return 1') { Ok ("{0}: mac unknown->no-reseed" -f $t.N) }
  else { Bad ("{0}: mac missing ok|unknown no-reseed" -f $t.N) }
}

Sec '2) HASH PARITY repo == Claude-Connect'
$pairs = @(
  @('connect.ps1',"$repo\windows\connect.ps1","$cc\connect.ps1"),
  @('connect-version.txt',"$repo\windows\connect-version.txt","$cc\connect-version.txt"),
  @('git-mode.ps1',"$repo\git-mode.ps1","$cc\git-mode.ps1"),
  @('editor-launch.ps1',"$repo\editor-launch.ps1","$cc\editor-launch.ps1"),
  @('mac/git-mode.sh',"$repo\git-mode.sh","$cc\mac\git-mode.sh"),
  @('mac/editor-launch.sh',"$repo\editor-launch.sh","$cc\mac\editor-launch.sh"),
  @('mac/connect.sh',"$repo\mac\connect.sh","$cc\mac\connect.sh"),
  @('mac/connect-version.txt',"$repo\mac\connect-version.txt","$cc\mac\connect-version.txt")
)
foreach ($p in $pairs) {
  if (-not (Test-Path $p[1]) -or -not (Test-Path $p[2])) { Bad ("missing " + $p[0]); continue }
  $a=(Get-FileHash $p[1] -Algorithm SHA256).Hash
  $b=(Get-FileHash $p[2] -Algorithm SHA256).Hash
  if ($a -eq $b) { Ok ("hash " + $p[0]) } else { Bad ("hash MISMATCH " + $p[0]) }
}

Sec '3) POWERSHELL PARSE'
foreach ($f in @(
  "$repo\git-mode.ps1","$repo\editor-launch.ps1","$repo\windows\connect.ps1","$repo\windows\connect-update.ps1",
  "$cc\git-mode.ps1","$cc\editor-launch.ps1","$cc\connect.ps1"
)) {
  $errs=$null
  $null=[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$null,[ref]$errs)
  if ($errs -and $errs.Count) { Bad ("parse " + (Split-Path $f -Leaf)); $errs | Select-Object -First 3 | ForEach-Object { Warn $_.ToString() } }
  else { Ok ("parse " + (Split-Path $f -Leaf)) }
}

Sec '4) FUNCTION CONTRACTS (dot-source)'
try {
  . "$repo\git-mode.ps1"
  foreach ($fn in @('Get-SocksProxyPort','Get-TunnelProxyLegState','Test-TunnelNeedsProxyReseed','Clear-LegacyDynamicSocksTunnels','Set-SocksProxyPortOnReuse')) {
    if (Get-Command $fn -EA SilentlyContinue) { Ok ("fn $fn") } else { Bad ("missing fn $fn") }
  }
  $meta = (Get-Command Clear-LegacyDynamicSocksTunnels).Parameters
  if ($meta.ContainsKey('SocksPort')) { Ok 'Clear-Legacy has SocksPort' } else { Bad 'Clear-Legacy missing SocksPort' }
} catch { Bad ("dot-source git-mode: " + $_.Exception.Message) }
try {
  . "$repo\editor-launch.ps1"
  foreach ($fn in @('Get-CursorRemoteProfileDir','Set-CursorProxySettings','Clear-CursorProxySettings','Get-CursorProxyLaunchArgs','Stop-CursorServerProfileTree')) {
    if (Get-Command $fn -EA SilentlyContinue) { Ok ("fn $fn") } else { Bad ("missing fn $fn") }
  }
  if (Get-Command Get-RunningCursorProxySocksPort -EA SilentlyContinue) { Bad 'Get-RunningCursorProxySocksPort must NOT exist on .38' }
  else { Ok 'no Get-RunningCursorProxySocksPort' }
  $args = @(Get-CursorProxyLaunchArgs)
  Ok ("Get-CursorProxyLaunchArgs count=$($args.Count)")
} catch { Bad ("dot-source editor-launch: " + $_.Exception.Message) }

Sec '5) LIVE SSH TUNNELS'
$legacyD=0; $goodL=0; $bare=0
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.Name -eq 'ssh.exe' -and $_.CommandLine -match '-N' -and $_.CommandLine -match '-R\s+\d+:localhost:22' -and
  $_.CommandLine -match '\bclaude-server(\s|$)' -and $_.CommandLine -notmatch 'sepidz'
} | ForEach-Object {
  $cmd = [string]$_.CommandLine
  if ($cmd -match '-L\s+127\.0\.0\.1:(1908\d):127\.0\.0\.1:10808') {
    $goodL++
    Ok ("-L pid=$($_.ProcessId) socks=$($Matches[1])")
  } elseif ($cmd -match '-D\s+127\.0\.0\.1:1908') {
    $legacyD++
    Bad ("legacy -D pid=$($_.ProcessId)")
  } else {
    $bare++
    Warn ("no-proxy-leg pid=$($_.ProcessId)")
  }
}
if ($goodL -ge 1) { Ok "-L count=$goodL" } else { Bad 'no -L tunnel live' }
if ($legacyD -eq 0) { Ok 'zero legacy -D' } else { Bad "legacy -D=$legacyD" }

Sec '6) SOCKS EGRESS + CURSOR API'
$working = @()
foreach ($p in 19080..19089) {
  $listen = $false
  try { $listen = [bool](Test-NetConnection 127.0.0.1 -Port $p -WarningAction SilentlyContinue -InformationLevel Quiet -EA SilentlyContinue) } catch {}
  if (-not $listen) { continue }
  $ip = & curl.exe -sS --max-time 10 --socks5-hostname "127.0.0.1:$p" https://api.ipify.org 2>$null
  $code = & curl.exe -sS -o NUL -w '%{http_code}' --max-time 12 --socks5-hostname "127.0.0.1:$p" https://api2.cursor.sh/ 2>$null
  if ($ip -eq '89.58.16.104' -and $code -eq '200') {
    $working += $p
    Ok "socks $p ip=$ip api2=$code"
  } else {
    Bad "socks $p ip=$ip api2=$code"
  }
}
if ($working.Count -ge 1) { Ok ("working_socks=$($working -join ',')") } else { Bad 'no working Austria socks' }

if ($working.Count -ge 1) {
  $p0 = $working[0]
  foreach ($u in @(
    'https://api2.cursor.sh/',
    'https://marketplace.cursorapi.com/',
    'https://www.cursor.com/',
    'https://api.github.com/'
  )) {
    $code = & curl.exe -sS -o NUL -w '%{http_code}' --max-time 15 --socks5-hostname "127.0.0.1:$p0" $u 2>$null
    if ($code -match '^(200|204|301|302|307|308|401|403|405)$') { Ok "$u -> $code" }
    else { Bad "$u -> $code" }
  }
  $direct = & curl.exe -sS --max-time 8 https://api.ipify.org 2>$null
  if ($direct -and $direct -ne '89.58.16.104') { Ok "direct egress=$direct (differs from Austria)" }
  elseif ($direct -eq '89.58.16.104') { Warn 'direct also Austria (machine may be on VPN)' }
  else { Warn 'direct egress unreachable' }
}

Sec '7) CURSOR SETTINGS + PROCESS FLAGS'
$s = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
$cliPorts = @()
if (-not (Test-Path $s)) { Bad 'settings.json missing' }
else {
  $j = Get-Content $s -Raw | ConvertFrom-Json
  $proxy = [string]$j.'http.proxy'
  if ($proxy -match '^socks5://127\.0\.0\.1:(1908\d)$') {
    $sp = [int]$Matches[1]
    Ok "http.proxy=$proxy"
    if ($working -contains $sp) { Ok "settings port $sp verified Austria+api2" }
    else { Bad "settings port $sp NOT in working socks ($($working -join ','))" }
  } else { Bad "http.proxy=$proxy" }
  if ("$($j.'http.proxySupport')" -eq 'override') { Ok 'proxySupport=override' } else { Bad "proxySupport=$($j.'http.proxySupport')" }
  if ($j.'cursor.general.disableHttp2' -eq $true) { Ok 'disableHttp2=true' } else { Bad 'disableHttp2' }
  if ($j.'http.proxyStrictSSL' -eq $false) { Ok 'proxyStrictSSL=false' } else { Bad "proxyStrictSSL=$($j.'http.proxyStrictSSL')" }
  if ("$($j.'cursor.general.proxyMode')" -eq 'custom') { Ok 'proxyMode=custom' } else { Bad "proxyMode=$($j.'cursor.general.proxyMode')" }
}

$mains = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.Name -match 'Cursor' -and $_.CommandLine -match 'ClaudeServerCursorProfile' -and $_.CommandLine -notmatch '--type='
})
$allCursor = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -match 'Cursor' })
Ok ("Cursor processes total=$($allCursor.Count) mains=$($mains.Count)")
if ($mains.Count -eq 0) {
  Bad 'no ClaudeServerCursorProfile main process'
} else {
  foreach ($p in $mains) {
    $c = [string]$p.CommandLine
    $hasP = $c -match '--proxy-server=socks5://127\.0\.0\.1:(1908\d)'
    $cliPort = if ($hasP) { [int]$Matches[1] } else { $null }
    $hasH2 = $c -match '--disable-http2'
    if ($hasP -and $hasH2) {
      Ok "Cursor pid=$($p.ProcessId) --proxy-server=:$cliPort --disable-http2"
      $cliPorts += $cliPort
      if ($working -contains $cliPort) { Ok "CLI port $cliPort verified" } else { Bad "CLI port $cliPort not verified" }
      if (Test-Path $s) {
        $sj = Get-Content $s -Raw | ConvertFrom-Json
        if ([string]$sj.'http.proxy' -eq "socks5://127.0.0.1:$cliPort") { Ok 'CLI port == settings port' }
        else { Bad ("CLI :$cliPort vs settings $($sj.'http.proxy')") }
      }
    } else {
      Bad "Cursor pid=$($p.ProcessId) missing CLI flags proxy=$hasP disableHttp2=$hasH2"
    }
  }
  $uniq = @($cliPorts | Select-Object -Unique)
  if ($uniq.Count -le 1) { Ok ("all mains same proxy port ($($uniq -join ','))") }
  else { Bad ("mains disagree on proxy ports: $($uniq -join ',')" ) }
}

Sec '8) .38 BEHAVIOR CONTRACT'
$el = Get-Content "$repo\editor-launch.ps1" -Raw
if ($el -match 'LAUNCH_KILL: reason=proxy_settings_changed soft-stop' -and $el -match 'Stop-CursorServerProfileTree') {
  Ok '.38 soft-stops on proxy_settings_changed'
} else { Bad 'missing soft-stop on proxy change' }
if ($el -match 'no soft-stop') { Bad 'still contains no soft-stop language' } else { Ok 'no preserve language' }
if ($el -match 'auth_relaunch_preserve') { Bad 'auth preserve still present' } else { Ok 'no auth preserve' }
if ($el -match 'reason=auth_relaunch soft-stop') { Ok 'auth relaunch soft-stops' } else { Bad 'auth relaunch soft-stop missing' }

$gm = Get-Content "$repo\git-mode.ps1" -Raw
if ($gm -match '\$procId = \[int\]\$p\.ProcessId' -and $gm -match 'Stop-TunnelProcessWithExitLog -ProcessId \$procId') {
  Ok 'legacy cleanup uses procId'
} else { Bad 'legacy cleanup procId contract' }
if ($gm -match '\[int\]\$SocksPort = 0') { Ok 'Clear-Legacy SocksPort param' } else { Bad 'Clear-Legacy SocksPort param' }
if ($gm -match 'reason=wait_timeout[\s\S]{0,160}\$script:SocksProxyPort = \$null') {
  Bad '.38 must NOT clear SocksProxyPort on wait_timeout'
} else { Ok 'wait_timeout does not clear SocksProxyPort' }

Sec '9) SERVER BUNDLE DIVERGENCE'
if (Test-Path $bundleNote) {
  $bv = (Get-Content $bundleNote -Raw).Trim()
  if ($bv -eq '20260721.42') {
    Ok "bundle still $bv (not deployed .38 - expected)"
    Warn 'connect.bat auto-update WILL overwrite local .38 with bundle .42'
  } elseif ($bv -eq '20260721.38') {
    Bad "bundle already .38 - unexpected without deploy approval"
  } else {
    Warn "bundle=$bv"
  }
} else {
  Warn 'bundle version note missing'
}

Sec '10) DAY LOG'
if (Test-Path $day) {
  $patterns = 'proxy_leg=-L|reuse_proxy ok|legacy_D_cleanup|proxy_settings_changed|CURSOR_PROXY_SET|ENSURE_TUNNEL|reseed_needed'
  $hits = @(Select-String -Path $day -Pattern $patterns -EA SilentlyContinue | Select-Object -Last 15)
  if ($hits.Count -gt 0) {
    Ok "recent proxy/tunnel log lines=$($hits.Count)"
    $hits | ForEach-Object {
      $line = $_.Line
      if ($line.Length -gt 160) { $line = $line.Substring(0,160) }
      Write-Host ("         " + $line)
    }
  } else { Warn 'no recent proxy lines in day log' }
} else { Warn 'no day log' }

Sec '11) ADVERSARIAL REGRESSION STRINGS'
$badHits = @(
  @{ F="$repo\editor-launch.ps1"; P='preserved_open_windows'; L='preserve' },
  @{ F="$repo\editor-launch.ps1"; P='Get-RunningCursorProxySocksPort'; L='align-fn' },
  @{ F="$repo\editor-launch.ps1"; P='CURSOR_PROXY_ALIGN'; L='align-log' },
  @{ F="$repo\git-mode.ps1"; P='listen_down'; L='listen_down' },
  @{ F="$repo\git-mode.sh"; P='listen_down'; L='mac listen_down' },
  @{ F="$repo\editor-launch.sh"; P='preserved_open_windows'; L='mac preserve' },
  @{ F="$repo\editor-launch.sh"; P='running_cursor_proxy_socks_port'; L='mac align' },
  @{ F="$repo\windows\connect-version.txt"; P='20260721\.(39|40|41|42)'; L='ver drift' },
  @{ F="$cc\connect-version.txt"; P='20260721\.(39|40|41|42)'; L='CC ver drift' }
)
foreach ($b in $badHits) {
  if (-not (Test-Path $b.F)) { Bad ("missing " + $b.F); continue }
  if (Select-String -Path $b.F -Pattern $b.P -Quiet) { Bad ("regression $($b.L) in $(Split-Path $b.F -Leaf)") }
  else { Ok ("clean $($b.L)") }
}

Sec 'SUMMARY'
Write-Host ("FAILS=$fail WARNS=$warn")
if ($fail -eq 0) { Write-Host 'HARD_TEST_ALL_PASSED'; exit 0 }
Write-Host 'HARD_TEST_FAILED'; exit 1
