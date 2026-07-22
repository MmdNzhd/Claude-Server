
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\windows-mcp-ensure.log'
Write-Output "LOG_PATH=$log"
Write-Output "LOG_EXISTS=$(Test-Path -LiteralPath $log)"
if (Test-Path -LiteralPath $log) {
  Write-Output '---TAIL---'
  Get-Content -LiteralPath $log -Tail 25
}
$runner = Join-Path $env:TEMP 'claude-connect-wmcp\ensure-bg.ps1'
Write-Output "RUNNER=$runner exists=$(Test-Path -LiteralPath $runner)"
# Any leftover ensure powershell?
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'ensure-bg|windows-mcp-laptop' } |
  Select-Object ProcessId, CommandLine |
  ForEach-Object { Write-Output ("PROC pid=$($_.ProcessId) cmd=$($_.CommandLine.Substring(0,[Math]::Min(160,$_.CommandLine.Length)))") }
# Health: port + auth
$listen = $false
try {
  $c = @(Get-NetTCPConnection -State Listen -LocalPort 8000 -EA SilentlyContinue | Where-Object { $_.LocalAddress -in @('127.0.0.1','::1','0.0.0.0') })
  $listen = $c.Count -gt 0
} catch {}
Write-Output "LISTEN=$listen"
$auth = Join-Path $env:USERPROFILE '.windows-mcp\auth.key'
Write-Output "AUTH_LEN=$(((Get-Content -LiteralPath $auth -Raw -EA SilentlyContinue)+'').Trim().Length)"
# Probe MCP with auth (streamable)
$key = ((Get-Content -LiteralPath $auth -Raw)+'').Trim()
try {
  $headers = @{ Authorization = "Bearer $key" }
  $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/mcp' -Headers $headers -Method GET -TimeoutSec 5 -UseBasicParsing -EA Stop
  Write-Output "LOCAL_MCP_HTTP=$($resp.StatusCode)"
} catch {
  $code = $null
  if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
  Write-Output "LOCAL_MCP_HTTP=$code err=$($_.Exception.Message.Substring(0,[Math]::Min(120,$_.Exception.Message.Length)))"
}
