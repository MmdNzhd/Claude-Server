$ErrorActionPreference = 'Continue'
Write-Host '==== 1) Cursor MAIN processes (profile) ===='
$mains = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'ClaudeServerCursorProfile' -and $_.CommandLine -notmatch '--type=' })
Write-Host ("main_count={0}" -f $mains.Count)
foreach ($p in $mains) {
  $socks = if ($p.CommandLine -match 'socks5://127\.0\.0\.1:(\d+)') { $Matches[1] } else { 'NONE' }
  $http = if ($p.CommandLine -match 'http://127\.0\.0\.1:(\d+)') { $Matches[1] } else { 'NONE' }
  Write-Host ("pid={0} cli_socks={1} cli_http={2}" -f $p.ProcessId, $socks, $http)
  Write-Host ("  cmd={0}" -f $p.CommandLine.Substring(0, [Math]::Min(280, $p.CommandLine.Length)))
}

Write-Host '==== 2) settings.json ===='
$prof = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
$sj = Get-Content $prof -Raw | ConvertFrom-Json
Write-Host ("http.proxy={0}" -f $sj.'http.proxy')
Write-Host ("http.proxySupport={0}" -f $sj.'http.proxySupport')
Write-Host ("disableHttp2={0}" -f $sj.'cursor.general.disableHttp2')

Write-Host '==== 3) ssh tunnel processes with -L proxy legs ===='
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match '1908|1918|10808|10809' } |
  ForEach-Object {
    $cl = $_.CommandLine
    $socks = [regex]::Matches($cl, '-L\s+127\.0\.0\.1:(1908\d):127\.0\.0\.1:10808') | ForEach-Object { $_.Groups[1].Value }
    $http  = [regex]::Matches($cl, '-L\s+127\.0\.0\.1:(1918\d):127\.0\.0\.1:10809') | ForEach-Object { $_.Groups[1].Value }
    Write-Host ("ssh_pid={0} socks_L={1} http_L={2}" -f $_.ProcessId, ($socks -join ','), ($http -join ','))
  }

function Test-Port([int]$Port) {
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(800)
    if (-not $ok) { $c.Close(); return $false }
    $c.EndConnect($iar); $c.Close(); return $true
  } catch { return $false }
}

Write-Host '==== 4) local ports listening ===='
foreach ($port in 19080,19081,19082,19180,19181,19182) {
  Write-Host ("port {0} tcp={1}" -f $port, (Test-Port $port))
}

function Probe-SocksEgress([int]$Port) {
  # Use curl if present: socks5h to fetch ifconfig.me via that proxy
  $curl = @(
    "$env:ProgramFiles\Git\mingw64\bin\curl.exe",
    "$env:ProgramFiles\Git\usr\bin\curl.exe",
    'C:\Windows\System32\curl.exe'
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $curl) { return "NO_CURL" }
  try {
    $out = & $curl -sS --max-time 12 --socks5-hostname "127.0.0.1:$Port" "https://api.ipify.org" 2>&1
    $code = $LASTEXITCODE
    return "exit=$code ip=$out"
  } catch {
    return "ERR $($_.Exception.Message)"
  }
}

function Probe-HttpProxy([int]$Port) {
  $curl = @(
    "$env:ProgramFiles\Git\mingw64\bin\curl.exe",
    "$env:ProgramFiles\Git\usr\bin\curl.exe",
    'C:\Windows\System32\curl.exe'
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $curl) { return "NO_CURL" }
  try {
    $out = & $curl -sS --max-time 12 -x "http://127.0.0.1:$Port" "https://api.ipify.org" 2>&1
    $code = $LASTEXITCODE
    return "exit=$code ip=$out"
  } catch {
    return "ERR $($_.Exception.Message)"
  }
}

Write-Host '==== 5) egress IP via each proxy (server xray path) ===='
Write-Host ("DIRECT(no proxy) = " + (& (Get-Command curl.exe).Source -sS --max-time 10 https://api.ipify.org 2>&1))
foreach ($sp in 19080,19081,19082) {
  if (Test-Port $sp) { Write-Host ("SOCKS $sp => $(Probe-SocksEgress $sp)") }
}
foreach ($hp in 19180,19181,19182) {
  if (Test-Port $hp) { Write-Host ("HTTP  $hp => $(Probe-HttpProxy $hp)") }
}

Write-Host '==== 6) MISMATCH verdict ===='
$cliSocks = @($mains | ForEach-Object {
  if ($_.CommandLine -match 'socks5://127\.0\.0\.1:(\d+)') { [int]$Matches[1] }
}) | Select-Object -Unique
$setProxy = [string]$sj.'http.proxy'
$setPort = if ($setProxy -match ':(\d+)$') { [int]$Matches[1] } else { $null }
Write-Host ("cli_socks_ports={0}" -f ($cliSocks -join ','))
Write-Host ("settings_http_proxy={0}" -f $setProxy)
$mismatch = $false
foreach ($cs in $cliSocks) {
  if ($setPort -and $cs -ne $setPort -and ($cs + 100) -ne $setPort) {
    # 19080 vs 19180 is same slot family OK; 19080 vs 19182 is different slot
    $slotCli = $cs % 10
    $slotSet = $setPort % 10
    if ($slotCli -ne $slotSet) { $mismatch = $true; Write-Host ("MISMATCH slot cli=$slotCli settings=$slotSet") }
  }
}
if ($cliSocks.Count -gt 1) { $mismatch = $true; Write-Host 'MISMATCH multiple Cursor mains on different socks ports' }
if ($mismatch) { Write-Host 'VERDICT=PROXY_STALE_OR_SPLIT' } else { Write-Host 'VERDICT=PORTS_ALIGNED_OR_SINGLE' }
