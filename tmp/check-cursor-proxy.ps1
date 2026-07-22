$ErrorActionPreference = 'Continue'
# What proxy is Cursor actually launched with / settings in profile?
$prof = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
Write-Host "PROFILE_SETTINGS=$prof exists=$([bool](Test-Path $prof))"
if (Test-Path $prof) {
  $j = Get-Content $prof -Raw | ConvertFrom-Json
  $keys = @('http.proxy','https.proxy','http.proxySupport','http.proxyStrictSSL','cursor.general.disableHttp2')
  foreach ($k in $keys) {
    $p = $j.PSObject.Properties[$k]
    if ($p) { Write-Host ("SETTING {0}={1}" -f $k, $p.Value) } else { Write-Host ("SETTING {0}=(absent)" -f $k) }
  }
}
# Live Cursor cmdline for profile
Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'ClaudeServerCursorProfile' -and $_.CommandLine -notmatch '--type=' } |
  Select-Object -First 3 ProcessId, CommandLine |
  ForEach-Object { Write-Host ("MAIN pid={0} cmd={1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(400,$_.CommandLine.Length))) }
# Local SOCKS/HTTP forward ports listening?
19080..19089 | ForEach-Object {
  $t = Test-NetConnection 127.0.0.1 -Port $_ -WarningAction SilentlyContinue -InformationLevel Quiet 2>$null
  if ($t) { Write-Host "LISTEN socks? $_ = $t" }
}
19180..19189 | ForEach-Object {
  $t = Test-NetConnection 127.0.0.1 -Port $_ -WarningAction SilentlyContinue -InformationLevel Quiet 2>$null
  if ($t) { Write-Host "LISTEN http? $_ = $t" }
}
