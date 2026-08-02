#Requires -Version 5.1
# Regression: windows-mcp must use per-UID server forward ports and a Hyper-V-safe
# laptop listen port (not shared 18000 / not blocked 8000).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== windows-mcp ports (client + server) ===' -ForegroundColor White

$mcp = Get-Content (Get-ClientFile 'windows\windows-mcp-laptop.ps1') -Raw
$fwd = Get-Content (Get-ServerFile 'server\windows-mcp-forward.sh') -Raw
$ref = Get-Content (Get-ServerFile 'server\skills\laptop-exec\reference-windows-mcp.md') -Raw

# --- Client: Hyper-V-safe local port ---
Assert ($mcp -match 'WindowsMcpLocalPortDefault\s*=\s*18765') 'Client default local port is 18765'
Assert ($mcp -match 'function\s+Get-WindowsMcpLocalPort') 'Get-WindowsMcpLocalPort exists'
Assert ($mcp -match 'function\s+Stop-WindowsMcpLegacyPort8000') 'Legacy :8000 killer exists'
Assert ($mcp -match 'never adopt legacy 8000|Never sticky-adopt') 'Port picker documents no sticky 8000 adopt'
Assert ($mcp -match 'Stop-WindowsMcpLegacyPort8000') 'Ensure/start path can migrate off :8000'
# Must not list 8000 in the already-listening adopt loop (sticky-adopt bug).
$adoptBlock = [regex]::Match($mcp, '(?s)Prefer an already-listening.*?foreach\s*\(\s*\$cand\s+in\s*@\(([^)]+)\)')
Assert ($adoptBlock.Success) 'Found already-listening candidate list'
Assert ($adoptBlock.Groups[1].Value -notmatch '\b8000\b') 'Already-listening adopt list excludes 8000'
Assert ($mcp -match 'function\s+Test-WindowsMcpPortBindable') 'Test-WindowsMcpPortBindable exists'
Assert ($mcp -match '7916|Hyper-V|10013') 'Client documents Hyper-V / WinError 10013 risk'
Assert ($mcp -match "WMCP_LPORT") 'Sync exports WMCP_LPORT to server'
Assert ($mcp -match "WINDOWS_MCP_LOCAL_PORT=' \+ str\(lport\)") 'Sync writes dynamic LOCAL_PORT (not hardcoding 8000)'
Assert ($mcp -notmatch "WINDOWS_MCP_LOCAL_PORT=8000'") 'Sync does not hardcode LOCAL_PORT=8000'
Assert ($mcp -match 'Get-WindowsMcpLocalPort') 'Client uses Get-WindowsMcpLocalPort helper'
# Start/auth/task paths must use \$lport / Get-WindowsMcpLocalPort, not bare --port 8000
$hard8000Serve = [regex]::Matches($mcp, '--port[''\s]+8000')
Assert ($hard8000Serve.Count -eq 0) 'No hardcoded --port 8000 in serve/auth/install paths'

# Live: default port bindable on this Windows host (or already listening)
$bindOk = $false
try {
    $existing = @(Get-NetTCPConnection -State Listen -LocalPort 18765 -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) { $bindOk = $true }
    else {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 18765)
        $l.Start(); $l.Stop(); $bindOk = $true
    }
} catch { $bindOk = $false }
Assert $bindOk 'Port 18765 is bindable (or already listening) on this laptop'

# Live: classic 8000 should be treated as unsafe when excluded (informational soft-check)
$excluded8000 = $false
try {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 8000)
    $l.Start(); $l.Stop()
} catch { $excluded8000 = $true }
if ($excluded8000) {
    Assert $true 'Port 8000 is excluded/unusable here (Hyper-V range) — default 18765 is required'
} else {
    Write-Host '  INFO  Port 8000 happens to be free on this host (exclusion ranges vary)' -ForegroundColor DarkGray
}

# --- Server: per-UID forward port + dedicated SSH (no mux) ---
Assert ($fwd -match '_default_wmcp_port') 'Server has per-UID default forward helper'
Assert ($fwd -match '28000 \+ uid - 1000|28000 \+ \$uid - 1000') 'Server formula is 28000+(UID-1000)'
Assert ($fwd -match 'WINDOWS_MCP_LOCAL_PORT:-\$?\{?18765\}?|WINDOWS_MCP_LOCAL_PORT:-18765') 'Server default LPORT is 18765'
Assert ($fwd -match 'ControlMaster=no') 'Forward disables ControlMaster'
Assert ($fwd -match 'ControlPath=none') 'Forward disables ControlPath'
Assert ($fwd -notmatch 'FPORT="\$\{WINDOWS_MCP_FORWARD_PORT:-18000\}"') 'Server does not default FPORT to shared 18000'

# Formula sanity for sample UIDs (pure arithmetic, mirrors bash)
function Get-ExpectedFwdPort([int]$Uid) {
    if ($Uid -ge 1000) {
        $p = 28000 + ($Uid - 1000)
        if ($p -gt 65535) { return 18000 }
        return $p
    }
    return 18000
}
Assert ((Get-ExpectedFwdPort 1002) -eq 28002) 'smart UID 1002 -> forward 28002'
Assert ((Get-ExpectedFwdPort 1007) -eq 28007) 'mehrdad UID 1007 -> forward 28007'
Assert ((Get-ExpectedFwdPort 1000) -eq 28000) 'UID 1000 -> forward 28000'
Assert ((Get-ExpectedFwdPort 999) -eq 18000) 'UID <1000 fallback 18000'

# Docs
Assert ($ref -match '18765') 'reference-windows-mcp.md documents laptop port 18765'
Assert ($ref -match '28000\+\(UID-1000\)') 'reference-windows-mcp.md documents per-UID forward'
Assert ($ref -notmatch '127\.0\.0\.1:8000') 'reference no longer teaches laptop :8000 as the product default'

# Never-again guards (amir: sync OK but forward dead; no keepalive)
Assert ($mcp -match 'WMCP_PROBE') 'Sync HTTP-probes forward (WMCP_PROBE)'
Assert ($mcp -match 'server_sync_probe_bad|server_sync_probe_ok') 'Sync logs probe result'
Assert ($mcp -match 'function\s+Maintain-WindowsMcpSession') 'Maintain-WindowsMcpSession exists'
Assert ($mcp -match 'listening but server forward/probe failed') 'Ensure fails closed when probe fails'
$wd = Get-Content (Get-ServerFile 'server\claude-watchdog.sh') -Raw
Assert ($wd -match 'windows-mcp-forward') 'Watchdog keeps windows-mcp-forward alive'
Assert ($fwd -match 'already healthy|leave live session') 'Forward leaves healthy live listeners alone'
$verify = Get-Content (Get-ServerFile 'server\commands\verify.sh') -Raw
Assert ($verify -match 'windows-mcp forward port') 'verify.sh checks per-UID windows-mcp ports'
$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($connect -match 'Maintain-WindowsMcpSession') 'connect.ps1 mid-session maintain hook'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
