#Requires -Version 5.1
# test-elevate-ssh-hard-batch.ps1
# HARD batch gate: elevate-when-needed, AdminFix RunAs, NEED_ADMIN/ADMIN_DENIED/ADMIN_UAC,
# admin_ak unreadable skip, cannot_read_ak, sshd readiness wait, firewall Profile Any,
# authorized_keys repair, Console Key+KeyChar for Persian layout (R/Q/C/X).
# ~14 Assert calls. Does NOT modify run-all.ps1.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$failed = 0
$passed = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "  PASS  $Msg" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Msg" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ''
Write-Host '=== test-elevate-ssh-hard-batch ===' -ForegroundColor Cyan
Write-Host ''

$winPath = Get-ClientFile 'windows\connect.ps1'
$gmPath = Get-ClientFile 'git-mode.ps1'
$win = Get-Content -LiteralPath $winPath -Raw
$gm = Get-Content -LiteralPath $gmPath -Raw

Write-Host '--- A) Elevate-when-needed (not always elevate) ---' -ForegroundColor DarkCyan

Assert ($win -match 'Elevate-when-needed') 'connect.ps1 documents elevate-when-needed'
$early = $win.Substring(0, [Math]::Min(3500, $win.Length))
Assert ($early -notmatch 'Verb RunAs') 'cold-start header has no Verb RunAs'
Assert ($win -match '\[switch\]\$AdminFix') 'AdminFix switch retained for on-demand elevate'

Write-Host '--- B) AdminFix RunAs + admin failure codes ---' -ForegroundColor DarkCyan

$adminOps = Get-FunctionSource -Content $win -Name 'Invoke-LaptopAdminOps'
Assert (
    $adminOps -and
    $adminOps -match 'Start-Process powershell\.exe -Verb RunAs' -and
    $adminOps -match "'-AdminFix'"
) 'Invoke-LaptopAdminOps elevates via RunAs -AdminFix'

Assert ($adminOps -match 'FAIL NEED_ADMIN:') 'Invoke-LaptopAdminOps logs FAIL NEED_ADMIN'
Assert ($adminOps -match 'FAIL ADMIN_DENIED:') 'Invoke-LaptopAdminOps logs FAIL ADMIN_DENIED on decline'
Assert ($adminOps -match 'FAIL ADMIN_UAC:') 'Invoke-LaptopAdminOps logs FAIL ADMIN_UAC on UAC/fix failure'

Write-Host '--- C) admin_ak unreadable / cannot_read_ak ---' -ForegroundColor DarkCyan

$akFn = Get-FunctionSource -Content $win -Name 'Test-AuthorizedKeyFragment'
$sshReady = Get-FunctionSource -Content $win -Name 'Test-LaptopSshReady'

Assert ($akFn -match 'cannot_read_ak') 'Test-AuthorizedKeyFragment logs cannot_read_ak on access denied'
Assert ($sshReady -match 'admin_ak unreadable unelevated') 'Test-LaptopSshReady skips admin_ak when unreadable unelevated'
Assert ($sshReady -match '\$null -eq \$akHit') 'Test-LaptopSshReady uses explicit null check (no false-positive NEED_ADMIN)'

Write-Host '--- D) sshd readiness wait + firewall Profile Any ---' -ForegroundColor DarkCyan

$installKey = Get-FunctionSource -Content $win -Name 'Install-ServerKey'
Assert (
    $installKey -and
    $installKey -match 'AddSeconds\(20\)' -and
    $installKey -match 'BeginConnect\(''127\.0\.0\.1'', 22' -and
    $installKey -match 'sshdReady'
) 'Install-ServerKey waits up to 20s for sshd TcpClient readiness'

Assert (
    ($adminOps -match '-Profile Any') -and
    ($win -match 'Set-NetFirewallRule -Name ''OpenSSH-Server-In-TCP''[\s\S]*-Profile Any')
) 'SSH firewall rule uses Profile Any (Invoke-LaptopAdminOps + AdminFix path)'

Write-Host '--- E) authorized_keys repair ---' -ForegroundColor DarkCyan

Assert (
    $installKey -and
    $installKey -match 'Repair-SshPerm' -and
    $installKey -match 'from=`"127\.0\.0\.1' -and
    $installKey -match 'administrators_authorized_keys'
) 'Install-ServerKey repairs authorized_keys with loopback restriction'

Write-Host '--- F) Console Key+KeyChar Persian layout (R/Q/C/X) ---' -ForegroundColor DarkCyan

Assert (
    $win -match 'KeyChar\.ToString\(\)' -and
    $win -match 'never for Persian/other printable non-ASCII' -and
    $win -match '\[ConsoleKey\]::R' -and
    $win -match '\[ConsoleKey\]::Q'
) 'Session loop resolves R/Q via KeyChar + VK fallback (Persian-safe)'

$postKeyFn = Get-FunctionSource -Content $gm -Name 'Read-PostDisconnectKey'
Assert (
    $postKeyFn -and
    $postKeyFn -match 'KeyChar\.ToString\(\)' -and
    $postKeyFn -match '\[ConsoleKey\]::C' -and
    $postKeyFn -match '\[ConsoleKey\]::X'
) 'Read-PostDisconnectKey resolves C/X via KeyChar + VK fallback'

Write-Host ''
Write-Host ("=== RESULT pass={0} fail={1} asserts={2} ===" -f $passed, $failed, ($passed + $failed)) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
