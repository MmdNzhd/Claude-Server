#Requires -Version 5.1
# test-harder-live-elevate-adminak.ps1
#
# HARDER LIVE gate (~14 Assert calls): elevate-when-needed / admin_ak contracts plus
# LIVE cannot_read_ak simulation via ACL-denied temp file using extracted
# Test-AuthorizedKeyFragment from connect.ps1 (verbatim, not reimplemented).
# Does NOT modify run-all.ps1 or production scripts.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

$SelfPath = $MyInvocation.MyCommand.Path
Write-Host ''
Write-Host '=== HARDER LIVE: elevate / admin_ak (Test-AuthorizedKeyFragment) ===' -ForegroundColor White
Write-Host ("  test={0}" -f $SelfPath) -ForegroundColor DarkGray
Write-Host ''

$winPath = Get-ClientFile 'windows\connect.ps1'
$gmPath = Get-ClientFile 'git-mode.ps1'
$win = Get-Content -LiteralPath $winPath -Raw
$gm = Get-Content -LiteralPath $gmPath -Raw

# ---------------------------------------------------------------------------
# A) Static deep: elevate-when-needed + admin failure codes
# ---------------------------------------------------------------------------
Write-Host '--- A) Static: elevate-when-needed + admin codes ---' -ForegroundColor DarkCyan

Assert ($win -match 'Elevate-when-needed') 'connect.ps1 documents elevate-when-needed'
$early = $win.Substring(0, [Math]::Min(3500, $win.Length))
Assert ($early -notmatch 'Verb RunAs') 'cold-start header has no Verb RunAs'
Assert ($win -match '\[switch\]\$AdminFix') 'AdminFix switch retained for on-demand elevate'

$adminOps = Get-FunctionSource -Content $win -Name 'Invoke-LaptopAdminOps'
Assert (
    $adminOps -and
    $adminOps -match 'Start-Process powershell\.exe -Verb RunAs' -and
    $adminOps -match "'-AdminFix'"
) 'Invoke-LaptopAdminOps elevates via RunAs -AdminFix'

Assert (
    $adminOps -match 'FAIL NEED_ADMIN:' -and
    $adminOps -match 'FAIL ADMIN_DENIED:' -and
    $adminOps -match 'FAIL ADMIN_UAC:'
) 'Invoke-LaptopAdminOps logs FAIL NEED_ADMIN / ADMIN_DENIED / ADMIN_UAC'

# ---------------------------------------------------------------------------
# B) Static deep: admin_ak unreadable contracts + firewall + Persian keys
# ---------------------------------------------------------------------------
Write-Host '--- B) Static: admin_ak / firewall / Persian KeyChar ---' -ForegroundColor DarkCyan

$akFnSrc = Get-FunctionSource -Content $win -Name 'Test-AuthorizedKeyFragment'
$sshReady = Get-FunctionSource -Content $win -Name 'Test-LaptopSshReady'

Assert (
    $akFnSrc -match 'cannot_read_ak' -and
    $sshReady -match 'admin_ak unreadable unelevated' -and
    $sshReady -match '\$null -eq \$akHit'
) 'admin_ak: cannot_read_ak log + unreadable skip + explicit null check'

Assert (
    ($adminOps -match '-Profile Any') -and
    ($win -match 'Set-NetFirewallRule -Name ''OpenSSH-Server-In-TCP''[\s\S]*-Profile Any')
) 'SSH firewall rule uses Profile Any (Invoke-LaptopAdminOps + AdminFix path)'

$postKeyFn = Get-FunctionSource -Content $gm -Name 'Read-PostDisconnectKey'
Assert (
    $win -match 'KeyChar\.ToString\(\)' -and
    $win -match '\[ConsoleKey\]::R' -and
    $win -match '\[ConsoleKey\]::Q' -and
    $postKeyFn -and
    $postKeyFn -match '\[ConsoleKey\]::C' -and
    $postKeyFn -match '\[ConsoleKey\]::X'
) 'Session R/Q + post-disconnect C/X via KeyChar + VK fallback (Persian-safe)'

# ---------------------------------------------------------------------------
# C) LIVE: extract Test-AuthorizedKeyFragment + ACL-denied cannot_read_ak
# ---------------------------------------------------------------------------
Write-Host '--- C) LIVE: ACL-denied cannot_read_ak (extracted function) ---' -ForegroundColor DarkCyan

Note 'extract Test-AuthorizedKeyFragment verbatim from connect.ps1'
Assert ($null -ne $akFnSrc) 'extracted Test-AuthorizedKeyFragment from connect.ps1'

$denyPath = $null
$okPath = $null
$testFrag = 'AAAAclaudeHarderLiveAdminAkTestFragmentZZZZ'

try {
    if ($akFnSrc) {
        $lc = New-Object System.Text.StringBuilder
        [void]$lc.AppendLine('$ErrorActionPreference = ''Continue''')
        [void]$lc.AppendLine('function Write-ConnectLog { param([string]$Msg, [string]$Level = ''INFO'') }')
        [void]$lc.AppendLine($akFnSrc)
        Invoke-Expression $lc.ToString()
    }

    Note 'LIVE ACL probe: deny Read for current user on temp authorized_keys-like file'
    $denyPath = Join-Path $env:TEMP ("claude-adminak-deny-" + [guid]::NewGuid().ToString('N') + '.txt')
    $okPath = Join-Path $env:TEMP ("claude-adminak-ok-" + [guid]::NewGuid().ToString('N') + '.txt')
    $line = "ssh-ed25519 $testFrag harder-live@test"
    Set-Content -LiteralPath $denyPath -Value $line -Encoding ASCII
    Set-Content -LiteralPath $okPath -Value $line -Encoding ASCII

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = Get-Acl -LiteralPath $denyPath
    $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $identity,
        [System.Security.AccessControl.FileSystemRights]::Read,
        [System.Security.AccessControl.AccessControlType]::Deny
    )
    $acl.AddAccessRule($denyRule)
    Set-Acl -LiteralPath $denyPath -AclObject $acl

    $directDenied = $false
    try {
        $null = Get-Content -LiteralPath $denyPath -ErrorAction Stop
    } catch {
        $directDenied = $true
        Note ("ACL probe: Get-Content denied as expected ({0})" -f $_.Exception.Message)
    }
    Assert $directDenied 'LIVE ACL probe: current user cannot read deny-file (simulates admin_ak ACL)'

    if (Get-Command Test-AuthorizedKeyFragment -ErrorAction SilentlyContinue) {
        $denyHit = Test-AuthorizedKeyFragment -Path $denyPath -PubFragment $testFrag
        Assert ($null -eq $denyHit) 'LIVE deny ACL: Test-AuthorizedKeyFragment returns $null (cannot_read_ak)'
        Assert ($denyHit -ne $false) 'LIVE deny ACL: $null is not $false (null-safe vs key missing)'

        $okHit = Test-AuthorizedKeyFragment -Path $okPath -PubFragment $testFrag
        $missHit = Test-AuthorizedKeyFragment -Path $okPath -PubFragment 'ZZZZnotInFileHarderLive'
        Assert ($okHit -eq $true) 'LIVE readable control: matching fragment returns $true'
        Assert ($missHit -eq $false) 'LIVE readable control: absent fragment returns $false'
    }

} catch {
    Write-Host ("  FAIL  LIVE admin_ak exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    foreach ($p in @($denyPath, $okPath)) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            try {
                $reset = Get-Acl -LiteralPath $p
                $reset.SetAccessRuleProtection($false, $true)
                Set-Acl -LiteralPath $p -AclObject $reset
            } catch {}
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ''
Write-Host ("HARDER LIVE ELEVATE ADMIN_AK: path={0}" -f $SelfPath) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("RESULT: {0} pass / {1} fail / {2} asserts" -f $Pass, $Fail, ($Pass + $Fail)) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
