#Requires -Version 5.1
# test-local-tunnel-ssh-pids.ps1 - Hardened local ssh -R PID matcher (Task 6)
# Table-driven pass/fail for required -R forms; behavioral stub of Get-LocalTunnelSshPids.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== local tunnel ssh pids matcher (Task 6) ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$shSrc = Get-Content -LiteralPath $shPath -Raw

Assert ($gmSrc -match 'function\s+Test-LocalTunnelSshCommandLine\b') `
    'static: Test-LocalTunnelSshCommandLine exists in git-mode.ps1'
Assert ($gmSrc -match 'function\s+Get-LocalTunnelSshPids\b') `
    'static: Get-LocalTunnelSshPids exists in git-mode.ps1'
Assert ($shSrc -match 'test_local_tunnel_ssh_command\s*\(') `
    'static: test_local_tunnel_ssh_command exists in git-mode.sh'
Assert ($shSrc -match 'get_local_tunnel_ssh_pids\s*\(') `
    'static: get_local_tunnel_ssh_pids exists in git-mode.sh'

. $gmPath

$TargetPort = 20021

$passRows = @(
    @{ Label = 'space localhost';     Cmd = "ssh.exe -N -R ${TargetPort}:localhost:22 claude-server" }
    @{ Label = 'space 127.0.0.1';     Cmd = "ssh.exe -N -R ${TargetPort}:127.0.0.1:22 claude-server" }
    @{ Label = 'equals localhost';    Cmd = "ssh.exe -N -R=${TargetPort}:localhost:22 claude-server" }
    @{ Label = 'double-space localhost'; Cmd = "ssh.exe -N -R  ${TargetPort}:localhost:22 claude-server" }
)

$failRows = @(
    @{ Label = 'wrong port';          Cmd = "ssh.exe -N -R 20022:localhost:22 claude-server" }
    @{ Label = 'wrong dest port';     Cmd = "ssh.exe -N -R ${TargetPort}:localhost:23 claude-server" }
    @{ Label = 'no -R ( -L )';       Cmd = "ssh.exe -N -L ${TargetPort}:localhost:22 claude-server" }
    @{ Label = 'no -R bare';         Cmd = "ssh.exe -N ${TargetPort}:localhost:22 claude-server" }
    @{ Label = 'no -R hostkey';      Cmd = "ssh-keygen -R ${TargetPort}:localhost:22" }
    @{ Label = 'wrong host';         Cmd = "ssh.exe -N -R ${TargetPort}:localhost:2222 claude-server" }
    @{ Label = 'concat no sep';      Cmd = "ssh.exe -N -R${TargetPort}:localhost:22 claude-server" }
)

foreach ($row in $passRows) {
    $ok = Test-LocalTunnelSshCommandLine -CommandLine $row.Cmd -TargetPort $TargetPort
    Assert $ok ("pass: $($row.Label)")
}

foreach ($row in $failRows) {
    $ok = Test-LocalTunnelSshCommandLine -CommandLine $row.Cmd -TargetPort $TargetPort
    Assert (-not $ok) ("fail: $($row.Label)")
}

# Behavioral: Get-LocalTunnelSshPids uses matcher against stubbed CIM rows
$stubPids = @(
    @{ ProcessId = 101; CommandLine = "ssh.exe -N -R ${TargetPort}:127.0.0.1:22 claude-server" }
    @{ ProcessId = 102; CommandLine = "ssh.exe -N -R=${TargetPort}:localhost:22 claude-server" }
    @{ ProcessId = 103; CommandLine = "ssh.exe -N -R 20022:localhost:22 claude-server" }
    @{ ProcessId = 104; CommandLine = "ssh.exe -N -L ${TargetPort}:localhost:22 claude-server" }
)

function Get-CimInstance {
    param([string]$Filter)
    if ($Filter -ne "Name='ssh.exe'") { return @() }
    return @($stubPids | ForEach-Object {
        [pscustomobject]@{ ProcessId = $_.ProcessId; CommandLine = $_.CommandLine }
    })
}

$found = @(Get-LocalTunnelSshPids -TargetPort $TargetPort)
Assert ($found.Count -eq 2) 'behavioral: Get-LocalTunnelSshPids returns only matching pids'
Assert ($found -contains 101) 'behavioral: finds 127.0.0.1 form pid=101'
Assert ($found -contains 102) 'behavioral: finds -R= form pid=102'
Assert ($found -notcontains 103) 'behavioral: rejects wrong port pid=103'
Assert ($found -notcontains 104) 'behavioral: rejects -L pid=104'

# Mac behavioral: same pass/fail table via extracted test_local_tunnel_ssh_command
$bashOk = $false
try {
    $probe = & bash -c "echo BASH_OK" 2>$null
    if ($LASTEXITCODE -eq 0 -and ($probe -join "`n") -match 'BASH_OK') { $bashOk = $true }
} catch { $bashOk = $false }

if (-not $bashOk) {
    Assert $false 'mac: bash unavailable - cannot run test_local_tunnel_ssh_command harness'
} else {
    function Convert-ToBashPath([string]$WinPath) {
        if ($WinPath -match '^([A-Za-z]):(.*)$') {
            return ('/mnt/' + $Matches[1].ToLower() + ($Matches[2] -replace '\\', '/'))
        }
        return ($WinPath -replace '\\', '/')
    }
    $shPathBash = Convert-ToBashPath $shPath
    $macHarness = @'
set -u
SCRIPT="__SCRIPT__"
TARGET_PORT="__PORT__"
FUNC_SRC="$(sed -n '/^test_local_tunnel_ssh_command()/,/^}/p' "$SCRIPT")"
[ -n "$FUNC_SRC" ] || { echo HARNESS_FAIL extract; exit 1; }
eval "$FUNC_SRC"
run_case() {
    local expect="$1" label="$2" cmd="$3" rc=0
    if test_local_tunnel_ssh_command "$TARGET_PORT" "$cmd"; then rc=0; else rc=1; fi
    if [ "$expect" = pass ] && [ "$rc" -eq 0 ]; then echo "PASS mac:$label"; return 0; fi
    if [ "$expect" = fail ] && [ "$rc" -ne 0 ]; then echo "PASS mac:$label"; return 0; fi
    echo "FAIL mac:$label expect=$expect rc=$rc"; exit 1
}
'@
    $macHarness = $macHarness.Replace('__SCRIPT__', $shPathBash).Replace('__PORT__', "$TargetPort")
    foreach ($row in $passRows) {
        $cmdEsc = ($row.Cmd -replace "'", "'\\''")
        $macHarness += "`nrun_case pass '$($row.Label)' '$cmdEsc'"
    }
    foreach ($row in $failRows) {
        $cmdEsc = ($row.Cmd -replace "'", "'\\''")
        $macHarness += "`nrun_case fail '$($row.Label)' '$cmdEsc'"
    }
    $macHarness = ($macHarness -replace "`r`n", "`n") -replace "`r", "`n"
    $tmpSh = [System.IO.Path]::Combine($PSScriptRoot, "_tmp_mac_tunnel_matcher_$([guid]::NewGuid().ToString('N')).sh")
    try {
        [System.IO.File]::WriteAllText($tmpSh, $macHarness, [System.Text.UTF8Encoding]::new($false))
        $tmpShBash = Convert-ToBashPath $tmpSh
        $macOut = & bash $tmpShBash 2>&1
        $macText = ($macOut -join "`n")
        foreach ($row in $passRows) {
            Assert ($macText -match "PASS mac:$([regex]::Escape($row.Label))") "mac pass: $($row.Label)"
        }
        foreach ($row in $failRows) {
            Assert ($macText -match "PASS mac:$([regex]::Escape($row.Label))") "mac fail: $($row.Label)"
        }
        Assert ($macText -notmatch 'FAIL mac:') 'mac: harness reported no FAIL lines'
    } finally {
        Remove-Item -LiteralPath $tmpSh -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All local-tunnel-ssh-pids tests passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} passed, {1} failed." -f $Pass, $Fail) -ForegroundColor Red
exit 1
