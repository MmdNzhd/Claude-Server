# test-agent-path-shared-p-hard.ps1
#
# Fleet 2026-08-03 deep-parallel W3:
#   AGENT_PATH bad reason=conf_port_closed session_port=20022 conf_port=20020
#   listen_conf=0 listen_session=1 primary_match=0
# Product contract (multi-Connect shared published TUNNEL_PORT):
#   - session!=conf + listen_conf=1 => AGENT_PATH ok (primary_match=0 is fine)
#   - conf_empty / probe_fail / conf truly closed => bad
#   - listen probe must retry (parallel Connect false listen_conf=0)
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert-C([string]$id, [bool]$ok, [string]$title, [string]$detail) {
  if ($ok) { Write-Host "PASS  [$id] $title"; Write-Host "      $detail" }
  else { Write-Host "HARD FAIL  [$id] $title"; Write-Host "      $detail"; $script:fail++ }
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'))) {
  $RepoRoot = 'D:\Smart\Claude-Code-Server'
}
$uiPath = Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'
$macPath = Join-Path $RepoRoot 'scripts/client/mac/connect.sh'
$ui = Get-Content -LiteralPath $uiPath -Raw
$mac = if (Test-Path -LiteralPath $macPath) { Get-Content -LiteralPath $macPath -Raw } else { '' }

Write-Host '=== AGENT_PATH shared-p hard ==='
Write-Host ("root={0}" -f $RepoRoot)
Write-Host ''

$probeFn = [regex]::Match($ui, '(?ms)^function Invoke-AgentPathProbe \{.*?^\}')
Assert-C 'S1' $probeFn.Success 'Invoke-AgentPathProbe parseable' $(if ($probeFn.Success) { 'ok' } else { 'missing' })
$probeBody = if ($probeFn.Success) { $probeFn.Value } else { '' }

# Remote listen check must retry (not a single timeout-1 /dev/tcp).
$hasRetry = ($probeBody -match 'AGENT_PATH_LISTEN_RETRY') -or (
  ($probeBody -match 'ss -ltn') -and ($probeBody -match 'for i in 1 2 3')
)
Assert-C 'S2' $hasRetry 'remote listen_conf probe retries (AGENT_PATH_LISTEN_RETRY or ss loop)' $(if ($hasRetry) { 'ok' } else { 'single-shot /dev/tcp only' })
$hasBudget = ($probeBody -match 'timeout 20') -or ($probeBody -match 'timeout\s+20')
Assert-C 'S2b' $hasBudget 'outer probe budget timeout 20 (covers retries + delayed recheck)' $(if ($hasBudget) { 'ok' } else { 'still timeout 15/5 or missing' })
$ssFirst = ($probeBody -match 'sport =') -or ($probeBody -match 'ss -ltn[\s\S]{0,160}/dev/tcp')
Assert-C 'S2c' $ssFirst 'ss sport=/listen check before /dev/tcp inside _ap_listen' $(if ($ssFirst) { 'ok' } else { 'tcp-before-ss or missing' })
Assert-C 'S2d' ($probeBody -match 'sleep 0\.45') 'delayed recheck when session live conf closed' 'ok'
Assert-C 'S2e' ($probeBody -match '\[s\]shfs') 'sshfs -p as listen evidence (shared-p false-neg belt)' 'ok'

# Shared-p: session!=conf must not alone be bad (comment or primary_match=0 ok path).
Assert-C 'S3' ($probeBody -match 'primary_match' -and $probeBody -match 'listen_conf') 'ok/bad keyed on listen_conf not session==conf' 'ok'

# Mac parity
Assert-C 'S4' ($mac -match '_agent_path_probe_if_due') 'Mac _agent_path_probe_if_due present' 'ok'
$macRetry = ($mac -match 'AGENT_PATH_LISTEN_RETRY') -or (($mac -match 'ss -ltn') -and ($mac -match 'for i in 1 2 3'))
Assert-C 'S5' $macRetry 'Mac listen probe also retries/ss' $(if ($macRetry) { 'ok' } else { 'Mac still single-shot' })

# --- Live classification via stubbed SshX ---
$live = Join-Path $env:TEMP ("agentpath-sp-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $live | Out-Null
$driver = Join-Path $live 'driver.ps1'
@'
param($UiPath, $Home2)
$ErrorActionPreference = 'Continue'
$env:USERPROFILE = $Home2
. $UiPath
$Alias = 'claude-server'
Initialize-ConnectLog -ScriptDir $Home2 -Version 'agentpath-sp'
$script:Port = 20022
$script:LastAgentPathUnix = 0

function SshX { param($Command) return @($script:StubProbe) }

function Invoke-Case([string]$name, [string]$probe, [bool]$expectOk) {
  $script:StubProbe = $probe
  $script:LastAgentPathUnix = 0
  $script:LastAgentPathResult = $null
  $script:ConnectLogSyncFailLogged = $false
  Invoke-AgentPathProbe
  try { $script:ConnectLogWriter.Flush() } catch { }
  $raw = Get-Content -LiteralPath $script:ConnectLogPath -Raw
  $okLine = [int]($raw -match ("AGENT_PATH ok[^\r\n]*session_port=20022"))
  $badLine = [int]($raw -match ("AGENT_PATH bad[^\r\n]*session_port=20022"))
  $gotOk = [bool]$script:LastAgentPathResult.Ok
  Write-Output ("CASE_{0}_RESULT_OK={1}" -f $name, [int]$gotOk)
  Write-Output ("CASE_{0}_LOG_OK={1}" -f $name, $okLine)
  Write-Output ("CASE_{0}_LOG_BAD={1}" -f $name, $badLine)
  Write-Output ("CASE_{0}_EXPECT_OK={1}" -f $name, [int]$expectOk)
}

# A: shared-p healthy — session!=conf, published port listening
Invoke-Case 'A' 'AGENT_PATH_PROBE conf_port=20020 conf_am=ai listen_conf=1 listen_session=1 session_port=20022' $true
# B: conf empty
Invoke-Case 'B' 'AGENT_PATH_PROBE conf_port= conf_am= listen_conf=0 listen_session=1 session_port=20022' $false
# C: conf closed (after reliable probe) — still bad for LE
Invoke-Case 'C' 'AGENT_PATH_PROBE conf_port=20020 conf_am=ai listen_conf=0 listen_session=1 session_port=20022' $false
# D: primary match healthy
$script:Port = 20020
Invoke-Case 'D' 'AGENT_PATH_PROBE conf_port=20020 conf_am=ai listen_conf=1 listen_session=1 session_port=20020' $true
'@ | Set-Content -LiteralPath $driver -Encoding UTF8

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $driver -UiPath $uiPath -Home2 $live 2>&1 | Out-String
Write-Host '--- live driver ---'
Write-Host $out

function Get-Flag([string]$text, [string]$name) {
  if ($text -match ("(?m)^{0}=(\d+)" -f [regex]::Escape($name))) { return [int]$Matches[1] }
  return -1
}

Assert-C 'L1' ((Get-Flag $out 'CASE_A_RESULT_OK') -eq 1) 'L1: shared-p session!=conf + listen_conf=1 => Ok' ('ok=' + (Get-Flag $out 'CASE_A_RESULT_OK'))
Assert-C 'L2' ((Get-Flag $out 'CASE_A_LOG_OK') -ge 1) 'L2: shared-p logs AGENT_PATH ok' ('log_ok=' + (Get-Flag $out 'CASE_A_LOG_OK'))
Assert-C 'L3' ((Get-Flag $out 'CASE_B_RESULT_OK') -eq 0) 'L3: conf_empty => bad' ('ok=' + (Get-Flag $out 'CASE_B_RESULT_OK'))
Assert-C 'L4' ((Get-Flag $out 'CASE_C_RESULT_OK') -eq 0) 'L4: listen_conf=0 => bad (LE uses published port)' ('ok=' + (Get-Flag $out 'CASE_C_RESULT_OK'))
Assert-C 'L4b' ($out -match 'conf_port_closed_session_live' -or (Get-Flag $out 'CASE_C_LOG_BAD') -ge 1) 'L4b: session_live shape named when listen_conf=0 listen_session=1' 'ok'
Assert-C 'L5' ((Get-Flag $out 'CASE_D_RESULT_OK') -eq 1) 'L5: primary match + listen => ok' ('ok=' + (Get-Flag $out 'CASE_D_RESULT_OK'))

Write-Host ''
Write-Host ("=== RESULT fail={0} ===" -f $fail)
if ($fail -gt 0) { Write-Host 'VERDICT: FAIL'; exit 1 }
Write-Host 'VERDICT: PASS'
exit 0
