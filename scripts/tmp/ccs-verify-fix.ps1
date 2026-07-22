$errs=$null;$tok=$null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\windows\connect.ps1'), [ref]$tok, [ref]$errs)
if ($errs) { 'PARSE_FAIL'; $errs } else { 'PARSE_OK connect' }
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\windows\cursor-proxy-sidecar.ps1'), [ref]$tok, [ref]$errs)
if ($errs) { 'PARSE_FAIL sidecar'; $errs } else { 'PARSE_OK sidecar' }
$s = Get-Content (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json') -Raw
if ($s -match '18998') { 'SETTINGS_OK 18998' } else { 'SETTINGS_BAD'; $s }
. .\scripts\client\git-mode.ps1
. .\scripts\client\windows\cursor-proxy-sidecar.ps1
Start-CursorProxySidecar | Out-Null
Repair-CursorProxySettingsToSidecar | Out-Null
# quick egress via http proxy
try {
  $wc = New-Object System.Net.WebClient
  $wc.Proxy = New-Object System.Net.WebProxy('http://127.0.0.1:18998')
  $ip = $wc.DownloadString('https://api.ipify.org').Trim()
  "PROXY_EGRESS_OK ip=$ip"
} catch {
  "PROXY_EGRESS_FAIL $($_.Exception.Message)"
}
