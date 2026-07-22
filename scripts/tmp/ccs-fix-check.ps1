$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Write-Host '=== LOG HITS ==='
if (Test-Path $log) {
  Select-String -Path $log -Pattern 'FAIL|ERROR|CURSOR_PROXY|PROXY_HEALTH|SIDECAR|LAUNCH_KILL|CONNECT_VERSION=20260721|ParseException|cannot be loaded' |
    Select-Object -Last 80 | ForEach-Object { $_.Line }
} else { Write-Host 'NO_LOG' }

Write-Host '=== PARSE ==='
$files = @(
  'scripts\client\windows\connect.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\editor-launch.ps1',
  'scripts\client\windows\cursor-proxy-sidecar.ps1',
  'scripts\client\windows\connect-update.ps1',
  'scripts\client\connect-ui.ps1'
)
foreach ($f in $files) {
  $errs = $null
  $tokens = $null
  $path = (Resolve-Path $f).Path
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
  if ($errs -and $errs.Count -gt 0) {
    Write-Host "PARSE_FAIL $f"
    foreach ($e in $errs) { Write-Host ("  {0}:{1} {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message) }
  } else {
    Write-Host "PARSE_OK $f"
  }
}

Write-Host '=== DOTSOURCE SMOKE ==='
try {
  . .\scripts\client\git-mode.ps1
  . .\scripts\client\editor-launch.ps1
  . .\scripts\client\windows\cursor-proxy-sidecar.ps1
  Write-Host ("SocksPortFn={0} HttpPortFn={1}" -f (Get-SocksProxyPort), (Get-HttpProxyPort))
  Write-Host ("HasClaim={0} HasHealth={0} HasSidecar={1}" -f (Get-Command Claim-CursorProxyOwner -ErrorAction SilentlyContinue), (Get-Command Start-CursorProxySidecar -ErrorAction SilentlyContinue))
  Write-Host ("FrontSocks={0} FrontHttp={1}" -f $script:CursorSocksFrontPort, $script:CursorHttpFrontPort)
} catch {
  Write-Host ("DOTSOURCE_FAIL {0}" -f $_.Exception.Message)
  Write-Host $_.ScriptStackTrace
}
