$ErrorActionPreference = 'Stop'
. .\scripts\client\git-mode.ps1
. .\scripts\client\windows\cursor-proxy-sidecar.ps1

function Get-CliProxyPorts {
  $ports = @()
  $prof = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
  Get-CimInstance Win32_Process -Filter "Name = 'Cursor.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    $cmd = [string]$_.CommandLine
    if ($cmd -notmatch [regex]::Escape($prof)) { return }
    if ($cmd -match '--proxy-server=socks5://127\.0\.0\.1:(\d+)') {
      $ports += [int]$Matches[1]
    }
  }
  return ($ports | Select-Object -Unique)
}

Write-Host '=== CLI proxy ports ==='
$cliPorts = @(Get-CliProxyPorts)
$cliPorts | ForEach-Object { Write-Host "cli_socks=$_" }

# Ensure fixed backends + sidecar front
$null = Start-CursorProxySidecar
$backSocks = 19080
$backHttp = 19180

# Emergency: relay any live CLI socks port -> 19080 so Chat works without kill
foreach ($p in $cliPorts) {
  if ($p -eq 18999 -or $p -eq 19080) { continue }
  Write-Host "EMERGENCY_RELAY socks $p -> $backSocks"
  try { Start-TcpPortRelay -ListenPort $p -BackendPort $backSocks -Name ("legacy_socks_" + $p) | Out-Null } catch { Write-Host $_.Exception.Message }
}
# Also relay matching http (socks+100)
foreach ($p in $cliPorts) {
  $http = $p + 100
  if ($http -eq 18998 -or $http -eq 19180) { continue }
  Write-Host "EMERGENCY_RELAY http $http -> $backHttp"
  try { Start-TcpPortRelay -ListenPort $http -BackendPort $backHttp -Name ("legacy_http_" + $http) | Out-Null } catch { Write-Host $_.Exception.Message }
}

# Force settings to sidecar HTTP front (undici)
$settingsPath = Join-Path (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User') 'settings.json'
$obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$obj.'http.proxy' = 'http://127.0.0.1:18998'
$obj | Add-Member -NotePropertyName 'https.proxy' -NotePropertyValue 'http://127.0.0.1:18998' -Force
($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $settingsPath -Encoding UTF8
Write-Host 'SETTINGS_FIXED http/https -> 18998'

# Verify
Write-Host '=== after ==='
Get-Content $settingsPath -Raw | Select-String 'proxy'
foreach ($p in (@(18999,18998,19080,19180) + $cliPorts + ($cliPorts | ForEach-Object { $_+100 }))) {
  $c = New-Object System.Net.Sockets.TcpClient
  $ok = $false
  try {
    $iar = $c.BeginConnect([System.Net.IPAddress]::Loopback, $p, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(400)
    if ($ok) { try { $c.EndConnect($iar); $ok = $c.Connected } catch { $ok = $false } }
  } catch { $ok = $false }
  finally { try { $c.Close() } catch {} }
  Write-Host ("port {0} open={1}" -f $p, $ok)
}
