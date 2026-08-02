# test-xray-socks-leg-resilience.ps1 - SOCKS -L leg retries ForceProbe before skip
# Callers: scripts/client/tests/run-all.ps1
#
# Guards the 2026-08-01 Aria empty socks_port= incident: Ensure-SessionTunnel treated a single
# inconclusive/timeout SOCKS probe like closed xray and cleared -L for the whole spawn. HTTP leg
# already retries with -ForceProbe (test-xray-http-leg-resilience.ps1); SOCKS must mirror that.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Xray SOCKS leg resilience ===' -ForegroundColor Cyan
Write-Host ''

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# Ensure-SessionTunnel is large; assert the SOCKS probe + ForceProbe retry order statically.
Assert ($gm -match 'remote_xray_socks=open_on_retry') 'logs SOCKS recovered-on-retry outcome'
Assert ($gm -match 'Test-RemoteXraySocksOpen[^\n]*-ForceProbe') 'SOCKS path re-probes with -ForceProbe'

$socksProbeIdx = $gm.IndexOf('$remoteSocksOk = Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath')
$forceIdx = $gm.IndexOf('Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath -ForceProbe')
$closedIdx = $gm.IndexOf('remote_xray_socks=closed')
Assert ($socksProbeIdx -ge 0) 'initial SOCKS probe present'
Assert ($forceIdx -ge 0 -and $socksProbeIdx -ge 0 -and $forceIdx -gt $socksProbeIdx) 'ForceProbe retry after first SOCKS probe'
Assert ($forceIdx -ge 0 -and $closedIdx -ge 0 -and $forceIdx -lt $closedIdx) 'ForceProbe retry happens BEFORE skipping_proxy_leg / closed'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
