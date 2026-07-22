$ErrorActionPreference = 'Stop'
$Expected = '20260721.38'
$Repo = Split-Path -Parent $PSScriptRoot
$Desktop = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$Failed = 0
$Warned = 0
$WorkingPorts = @()
function Pass([string]$m) { Write-Host "PASS  $m" -ForegroundColor Green }
function Fail([string]$m) { $script:Failed++; Write-Host "FAIL  $m" -ForegroundColor Red }
function Warn([string]$m) { $script:Warned++; Write-Host "WARN  $m" -ForegroundColor Yellow }
function Check([bool]$ok, [string]$m) { if ($ok) { Pass $m } else { Fail $m } }
function SHA([string]$p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash } else { $null } }
function Text([string]$p) { if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) } else { $null } }
function CmdLine($p) { if ($null -eq $p.CommandLine) { '' } else { [string]$p.CommandLine } }
function Http([string]$url, [string]$proxy = $null) {
  try {
    $a = @{ Uri = $url; UseBasicParsing = $true; TimeoutSec = 20; ErrorAction = 'Stop' }
    if ($proxy) { $a.Proxy = $proxy }
    $r = Invoke-WebRequest @a
    [pscustomobject]@{ Ok = $true; Code = [int]$r.StatusCode; Body = [string]$r.Content; Error = '' }
  } catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    [pscustomobject]@{ Ok = $false; Code = $code; Body = ''; Error = $_.Exception.Message }
  }
}
function AllowedCode([int]$code) { @(200,301,302,307,308,401,403,405) -contains $code }
Write-Host '=== DEEP LIVE RUNTIME AUDIT .38 ==='
Write-Host "repo=$Repo"
Write-Host "desktop=$Desktop"
Check (Test-Path -LiteralPath $Desktop) 'Desktop Claude-Connect exists'
$repoWin = Join-Path $Repo 'scripts\client\windows'
$repoMac = Join-Path $Repo 'scripts\client\mac'
$versionFiles = @(
  (Join-Path $repoWin 'connect.ps1'), (Join-Path $repoMac 'connect.sh'),
  (Join-Path $repoWin 'connect-version.txt'), (Join-Path $repoMac 'connect-version.txt'),
  (Join-Path $Desktop 'connect.ps1'), (Join-Path $Desktop 'connect-version.txt')
)
foreach ($p in $versionFiles) { Check ((Text $p) -match [regex]::Escape($Expected)) "version $p is $Expected" }
$winText = Text (Join-Path $repoWin 'connect.ps1')
$macText = Text (Join-Path $repoMac 'connect.sh')
Check ($winText -match "ConnectVersion\s*=\s*'$Expected'") 'repo ConnectVersion exact'
Check ($macText -match "CONNECT_VERSION='$Expected'") 'repo CONNECT_VERSION exact'
$required = @('Test-TunnelNeedsProxyReseed','Never mass-kill','Get-CursorProxyLaunchArgs','proxy_settings_changed','proxyStrictSSL false')
$forbidden = @('preserved_open_windows','Get-RunningCursorProxySocksPort','CURSOR_PROXY_ALIGN','auth_relaunch_preserve','listen_down')
$allClientText = (Get-ChildItem -LiteralPath $repoWin,$repoMac -File -Recurse | ForEach-Object { Text $_.FullName }) -join "`n"
foreach ($x in $required) { Check ($allClientText -match [regex]::Escape($x)) "required marker present: $x" }
foreach ($x in $forbidden) { Check ($allClientText -notmatch [regex]::Escape($x)) "forbidden marker absent: $x" }
$hashPairs = @(
  @('connect.ps1','scripts\client\windows\connect.ps1'),
  @('connect-version.txt','scripts\client\windows\connect-version.txt'),
  @('git-mode.ps1','scripts\client\windows\git-mode.ps1'),
  @('editor-launch.ps1','scripts\client\editor-launch.ps1'),
  @('mac\git-mode.sh','scripts\client\mac\git-mode.sh'),
  @('mac\editor-launch.sh','scripts\client\editor-launch.sh'),
  @('mac\connect.sh','scripts\client\mac\connect.sh'),
  @('mac\connect-version.txt','scripts\client\mac\connect-version.txt')
)
foreach ($pair in $hashPairs) {
  $left = Join-Path $Desktop $pair[0]; $right = Join-Path $Repo $pair[1]
  $h1 = SHA $left; $h2 = SHA $right
  Check (($null -ne $h1) -and ($h1 -eq $h2)) "SHA256 Desktop/$($pair[0]) equals repo/$($pair[1])"
}
$parseFiles = @((Join-Path $repoWin 'connect.ps1'),(Join-Path $repoWin 'git-mode.ps1'),(Join-Path $Repo 'scripts\client\editor-launch.ps1'))
foreach ($p in $parseFiles) {
  $tokens = $null; $errors = $null; [void][Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  Check ($errors.Count -eq 0) "PowerShell parser zero errors: $p"
}
$bashFiles = @('scripts/client/mac/git-mode.sh','scripts/client/editor-launch.sh','scripts/client/mac/connect.sh')
foreach ($rel in $bashFiles) {
  $p = Join-Path $Repo $rel; $r = & bash -n $p 2>&1; Check ($LASTEXITCODE -eq 0) "bash -n: $rel"; if ($LASTEXITCODE -ne 0) { Write-Host $r }
}
$ssh = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" | Where-Object { (CmdLine $_) -match '(^|\s)-N(\s|$)' -and (CmdLine $_) -match 'claude-server' -and (CmdLine $_) -notmatch 'sepidz' })
Write-Host "--- LIVE TUNNELS ($($ssh.Count)) ---"
$liveLTunnels = @()
foreach ($p in $ssh) {
  $c = CmdLine $p; $kind = if ($c -match '(^|\s)-D(\s|\d|:)') { 'D' } elseif ($c -match '(^|\s)-L(\s|\d|:)') { 'L' } else { 'bare' }
  Write-Host "pid=$($p.ProcessId) kind=$kind $c"
  if ($kind -eq 'D') { Fail "dynamic SOCKS tunnel found pid=$($p.ProcessId)" }
  if ($kind -eq 'L') { $liveLTunnels += $p }
}
$xrayExpected = $allClientText -match '1908[0-9]'
if ($xrayExpected) { Check ($liveLTunnels.Count -gt 0) 'at least one live -L tunnel for xray' }
$listen = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -ge 19080 -and $_.LocalPort -le 19089 })
Write-Host "--- SOCKS LISTENERS ($($listen.Count)) ---"
foreach ($l in $listen) {
  $port = [int]$l.LocalPort; $proxy = "socks5://127.0.0.1:$port"; Write-Host "port=$port pid=$($l.OwningProcess)"
  $ip = Http 'https://api.ipify.org' $proxy
  Check ($ip.Ok -and $ip.Body.Trim() -eq '89.58.16.104') "SOCKS $port api.ipify is Austria expected IP"
  $cursor = Http 'https://api2.cursor.sh' $proxy
  Check ($cursor.Code -eq 200) "SOCKS $port api2.cursor.sh HTTP 200"
  if ($ip.Ok -and $ip.Body.Trim() -eq '89.58.16.104' -and $cursor.Code -eq 200) { $WorkingPorts += $port }
}
Check ($WorkingPorts.Count -gt 0) 'at least one fully working SOCKS listener'
if ($WorkingPorts.Count -gt 0) {
  $proxy = "socks5://127.0.0.1:$($WorkingPorts[0])"
  foreach ($u in @('https://marketplace.cursorapi.com','https://cursor.com','https://api.github.com')) {
    $r = Http $u $proxy; Check (AllowedCode $r.Code) "SOCKS $($WorkingPorts[0]) $u allowed status ($($r.Code))"
  }
}
$direct = Http 'https://api.ipify.org'
if ($direct.Ok) { if ($direct.Body.Trim() -eq '89.58.16.104') { Warn 'direct api.ipify is Austria; expected office/non-Austria' } elseif ($direct.Body.Trim() -eq '188.40.20.144') { Pass 'direct api.ipify is office IP' } else { Warn "direct api.ipify unexpected non-Austria IP: $($direct.Body.Trim())" } } else { Warn "direct api.ipify failed: $($direct.Error)" }
$profile = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
$settingsText = Text $profile
Check ($null -ne $settingsText) 'ClaudeServerCursorProfile settings.json exists'
if ($settingsText) {
  try { $settings = $settingsText | ConvertFrom-Json -ErrorAction Stop } catch { $settings = $null; Fail "profile settings invalid JSON: $($_.Exception.Message)" }
  if ($settings) {
    $proxyValue = [string]$settings.'http.proxy'; $portMatch = [regex]::Match($proxyValue,'1908[0-9]')
    Check ($proxyValue -match '^socks5://127\.0\.0\.1:1908[0-9]$') 'profile http.proxy is local SOCKS 1908x'
    Check ([bool]$settings.'http.proxySupport') 'profile proxy override configured'
    Check ($settings.'http.disableHttp2' -eq $true) 'profile disableHttp2 true'
    Check ($settings.'http.proxyStrictSSL' -eq $false) 'profile strictSSL false'
    Check ($settings.'http.proxyMode' -eq 'custom') 'profile proxyMode custom'
    if ($portMatch.Success) { $settingsPort = [int]$portMatch.Value; Check ($WorkingPorts -contains $settingsPort) "profile proxy port $settingsPort is fully working" } else { $settingsPort = $null }
  }
}
$cursorProcs = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'")
$serverMains = @($cursorProcs | Where-Object { (CmdLine $_) -match 'ClaudeServerCursorProfile' -and (CmdLine $_) -notmatch '(^|\s)--type=' })
$personal = @($cursorProcs | Where-Object { (CmdLine $_) -notmatch 'ClaudeServerCursorProfile' })
Write-Host "--- CURSOR processes total=$($cursorProcs.Count) server-mains=$($serverMains.Count) personal=$($personal.Count) ---"
$mainPorts = @()
foreach ($p in $serverMains) {
  $c = CmdLine $p; Write-Host "server-main pid=$($p.ProcessId) $c"
  Check ($c -match '--proxy-server=socks5://127\.0\.0\.1:1908[0-9]') "Cursor main $($p.ProcessId) has proxy-server"
  Check ($c -match '--disable-http2') "Cursor main $($p.ProcessId) has disable-http2"
  $m = [regex]::Match($c,'--proxy-server=socks5://127\.0\.0\.1:(1908[0-9])'); if ($m.Success) { $mainPorts += [int]$m.Groups[1].Value; Check ($WorkingPorts -contains [int]$m.Groups[1].Value) "Cursor main $($p.ProcessId) proxy port works" }
}
Check ($serverMains.Count -gt 0) 'at least one ClaudeServerCursorProfile main process'
if ($mainPorts.Count -gt 0) { Check (($mainPorts | Select-Object -Unique).Count -eq 1) 'all server Cursor mains use one proxy port'; if ($settingsPort) { Check (($mainPorts | Select-Object -Unique)[0] -eq $settingsPort) 'Cursor main proxy matches profile settings' } }
. (Join-Path $repoWin 'git-mode.ps1')
. (Join-Path $Repo 'scripts\client\editor-launch.ps1')
foreach ($fn in @('Get-TunnelProxyLegState','Clear-LegacyDynamicSocksTunnels','Get-CursorProxyLaunchArgs')) { Check ($null -ne (Get-Command $fn -ErrorAction SilentlyContinue)) "function exists: $fn" }
Check ($null -eq (Get-Command 'Get-RunningCursorProxySocksPort' -ErrorAction SilentlyContinue)) 'removed function absent: Get-RunningCursorProxySocksPort'
if ($liveLTunnels.Count -gt 0) {
  $pid = [int]$liveLTunnels[0].ProcessId; $state = Get-TunnelProxyLegState -TunnelPid $pid
  Check ($state -eq 'ok') "Get-TunnelProxyLegState live -L pid $pid is ok (got $state)"
  $port = if ($WorkingPorts.Count) { $WorkingPorts[0] } else { 19080 }
  $killed = Clear-LegacyDynamicSocksTunnels -SocksPort $port -ProtectPid $pid
  Check ($killed -eq 0) "Clear-LegacyDynamicSocksTunnels killed zero unprotected -D tunnels"
}
$logs = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$latest = Get-ChildItem -LiteralPath $logs -Filter 'connect-*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
  Write-Host "--- DAY LOG $($latest.FullName) ---"
  $hits = @(Get-Content -LiteralPath $latest.FullName | Where-Object { $_ -match 'proxy|tunnel|legacy_D_cleanup|LAUNCH_KILL|proxy_settings_changed|mass' } | Select-Object -Last 20)
  $hits | ForEach-Object { Write-Host $_ }
  $allLog = Get-Content -LiteralPath $latest.FullName
  Check (-not ($allLog -match 'LAUNCH_KILL.*proxy_settings_changed|proxy_settings_changed.*LAUNCH_KILL')) 'no LAUNCH_KILL proxy_settings_changed mass event'
  $large = @($allLog | Where-Object { $_ -match 'legacy_D_cleanup' -and $_ -match '(killed=|killed )([1-9][0-9]|[1-9][0-9][0-9])' })
  Check ($large.Count -eq 0) 'no large legacy_D_cleanup kill event'
} else { Fail 'no connect day log found' }
Write-Host '--- BUNDLE DIVERGENCE COMPARE OUTPUT ---'
foreach ($rel in @('scripts\client\windows\git-mode.ps1','scripts\client\editor-launch.ps1')) { Write-Host "repo $rel $(SHA (Join-Path $Repo $rel))" }
Write-Host "FAILED=$Failed WARNED=$Warned"
if ($Failed -gt 0) { exit 1 } else { exit 0 }
