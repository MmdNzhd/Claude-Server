
$ErrorActionPreference = 'Stop'
$fail = @()
function Ok($m){ Write-Output "OK  $m" }
function Bad($m){ $script:fail += $m; Write-Output "BAD $m" }

# 1) Parse
foreach ($rel in @('scripts/client/windows/windows-mcp-laptop.ps1','scripts/client/windows/connect.ps1')) {
  $errs = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $rel).Path, [ref]$null, [ref]$errs)
  if ($errs -and $errs.Count) { Bad "parse $rel : $($errs[0])" } else { Ok "parse $rel" }
}

# 2) Version consistency
$verPs = (Select-String -Path 'scripts/client/windows/connect.ps1' -Pattern "ConnectVersion = '([^']+)'").Matches[0].Groups[1].Value
$verTxt = (Get-Content -LiteralPath 'scripts/client/windows/connect-version.txt' -Raw).Trim()
if ($verPs -eq $verTxt -and $verPs -eq '20260722.02') { Ok "version=$verPs" } else { Bad "version ps=$verPs txt=$verTxt" }

# 3) No sync Step UI for Windows-MCP
$raw = Get-Content -LiteralPath 'scripts/client/windows/connect.ps1' -Raw
if ($raw -match "Step 'Windows-MCP'") { Bad "sync Step Windows-MCP still present" } else { Ok "no blocking Step UI" }
if ($raw -match 'Start-WindowsMcpEnsureBackground') { Ok "background kick wired" } else { Bad "background kick missing" }
if ($raw -match 'Ensure-WindowsMcp\s*\r?\n' -and $raw -notmatch 'Start-WindowsMcpEnsureBackground') { Bad "sync Ensure still called" }
# sync Ensure call as direct invoke in connect (not in comments)
if ($raw -match '\$wmcp = Ensure-WindowsMcp') { Bad "sync Ensure-WindowsMcp call remains" } else { Ok "connect does not await Ensure" }

# 4) Dot-source + function exports
. (Resolve-Path 'scripts/client/windows/windows-mcp-laptop.ps1').Path
foreach ($fn in @('Ensure-WindowsMcp','Start-WindowsMcpEnsureBackground','Test-WindowsMcpListening','Get-WindowsMcpExe')) {
  if (Get-Command $fn -EA SilentlyContinue) { Ok "fn $fn" } else { Bad "fn missing $fn" }
}

# 5) publish + bat include
$pub = Get-Content -LiteralPath 'publish/publish.ps1' -Raw
if ($pub -match 'windows-mcp-laptop\.ps1') { Ok 'publish includes module' } else { Bad 'publish missing module' }
$bat = Get-Content -LiteralPath 'scripts/client/windows/connect.bat' -Raw
if ($bat -match "windows-mcp-laptop\.ps1") { Ok 'bat heal/outdated lists module' } else { Bad 'bat missing module' }

# 6) Background spawn smoke (must return quickly)
$sw = [Diagnostics.Stopwatch]::StartNew()
$script:WindowsMcpBgStarted = $false
$mod = (Resolve-Path 'scripts/client/windows/windows-mcp-laptop.ps1').Path
$started = Start-WindowsMcpEnsureBackground -ModulePath $mod -SshAlias 'claude-server'
$sw.Stop()
$kickMs = [int]$sw.ElapsedMilliseconds
if (-not $started) { Bad 'background start returned false' } else { Ok "background kick returned in ${kickMs}ms" }
if ($kickMs -gt 3000) { Bad "kick too slow ${kickMs}ms (should be fire-and-forget)" } else { Ok "kick latency ok (<3s)" }

# 7) Wait for ensure progress / listening
$listenBefore = Test-WindowsMcpListening
$deadline = (Get-Date).AddSeconds(45)
$listenAfter = $false
do {
  Start-Sleep -Seconds 2
  $listenAfter = Test-WindowsMcpListening
} while (-not $listenAfter -and (Get-Date) -lt $deadline)

$exe = Get-WindowsMcpExe
if ($exe) { Ok "exe present: $exe" } else { Bad 'windows-mcp.exe missing after ensure window' }
if ($listenAfter) { Ok 'listening on :8000' } else { Bad 'not listening on :8000 within 45s (desktop locked/session0?)' }

$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\windows-mcp-ensure.log'
if (Test-Path -LiteralPath $log) {
  $tail = Get-Content -LiteralPath $log -Tail 8
  Ok "ensure log exists"
  $tail | ForEach-Object { Write-Output "LOG $_" }
} else {
  Bad 'ensure log missing'
}

# 8) Auth key present
$auth = Join-Path $env:USERPROFILE '.windows-mcp\auth.key'
if ((Test-Path $auth) -and ((Get-Content $auth -Raw).Trim().Length -ge 32)) { Ok 'auth.key present' } else { Bad 'auth.key missing/short' }

# 9) Task registered
$task = Get-ScheduledTask -TaskName 'windows-mcp-server' -EA SilentlyContinue
if ($task) { Ok "task state=$($task.State)" } else { Bad 'scheduled task missing' }

# 10) Idempotent second kick should no-op fast
$sw2 = [Diagnostics.Stopwatch]::StartNew()
$started2 = Start-WindowsMcpEnsureBackground -ModulePath $mod -SshAlias 'claude-server'
$sw2.Stop()
if ($started2 -and $sw2.ElapsedMilliseconds -lt 500) { Ok "second kick no-op $($sw2.ElapsedMilliseconds)ms" } else { Ok "second kick result=$started2 ms=$([int]$sw2.ElapsedMilliseconds)" }

Write-Output '---'
if ($fail.Count -eq 0) { Write-Output 'ALL_OK'; exit 0 }
Write-Output ('FAIL_COUNT=' + $fail.Count)
$fail | ForEach-Object { Write-Output ("FAIL: " + $_) }
exit 1
