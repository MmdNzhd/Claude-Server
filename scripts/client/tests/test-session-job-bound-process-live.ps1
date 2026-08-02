# test-session-job-bound-process-live.ps1
# LIVE proof: Start-JobBoundProcess assigns children to a KILL_ON_JOB_CLOSE session job
# so when the OWNER process exits (simulated Connect force-close / crash), Windows kills
# the child. This is real process lifetime, not mocked API success codes.
#
# Also asserts static contracts: deferred setup / mount-bg / windows-mcp background
# go through Start-JobBoundProcess (with Start-Process fail-open fallback).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Session Start-JobBoundProcess (LIVE parent-exit kill) ===' -ForegroundColor Cyan

$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$mcp = Get-Content (Get-ClientFile 'windows\windows-mcp-laptop.ps1') -Raw

foreach ($n in @('Initialize-ConnectSessionJob', 'Add-ConnectSessionJobProcess', 'Stop-ConnectSessionJob', 'Start-JobBoundProcess')) {
    Assert ($gitMode -match "function\s+$n\b") "git-mode.ps1 defines $n"
}
Assert ($gitMode -match 'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE') 'session job uses KILL_ON_JOB_CLOSE'
Assert ($gitMode -match 'ClaudeConnectSessionJob') 'session job type is distinct from sidecar ClaudeConnectSidecarJob'
Assert ($connect -match 'Start-JobBoundProcess') 'connect.ps1 uses Start-JobBoundProcess for session helpers'
Assert ($connect -match '(?s)function\s+Start-DeferredServerSetup.*?Start-JobBoundProcess') 'DeferredServerSetup goes through Start-JobBoundProcess'
Assert ($connect -match '(?s)function\s+Start-MountProjectBackground.*?Start-JobBoundProcess') 'MountProjectBackground goes through Start-JobBoundProcess'
Assert ($mcp -match '(?s)function\s+Start-WindowsMcpEnsureBackground.*?Start-JobBoundProcess') 'Windows-MCP background ensure goes through Start-JobBoundProcess'
# Keep Win32 job APIs out of connect.ps1 (sidecar + git-mode own them).
Assert ($connect -notmatch 'CreateJobObject|AssignProcessToJobObject') 'connect.ps1 has no raw Job Object P/Invoke (stays in git-mode / sidecar)'

# Extract real shipped functions into this process for a direct assign/close sanity check,
# then run the parent-exit scenario in a short-lived child PowerShell.
foreach ($n in @('Initialize-ConnectSessionJob', 'Add-ConnectSessionJobProcess', 'Stop-ConnectSessionJob', 'Start-JobBoundProcess')) {
    $src = Get-FunctionSource -Content $gitMode -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

Write-Host ''
Write-Host '--- A) Direct job-close kills assigned member (baseline) ---' -ForegroundColor Yellow
$member = $null
$control = $null
try {
    $member = Start-JobBoundProcess -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 120'
    ) -WindowStyle Hidden -PassThru
    $control = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 120'
    ) -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 400
    Assert ($member -and -not $member.HasExited) 'A: job-bound member actually started'
    Assert ($control -and -not $control.HasExited) 'A: unbound control actually started'
    Stop-ConnectSessionJob
    $deadline = (Get-Date).AddSeconds(6)
    $memberDead = $false
    while ((Get-Date) -lt $deadline) {
        if ($member.HasExited) { $memberDead = $true; break }
        Start-Sleep -Milliseconds 200
    }
    Assert $memberDead 'A: closing session job handle kills the Start-JobBoundProcess child (real KILL_ON_JOB_CLOSE)'
    Assert (-not $control.HasExited) 'A: unbound control survives - no blast radius outside the job'
} finally {
    foreach ($p in @($member, $control)) {
        if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
    }
    try { Stop-ConnectSessionJob } catch {}
}

Write-Host ''
Write-Host '--- B) Owner process exit kills grandchild (Connect force-close simulation) ---' -ForegroundColor Yellow
$tmpDir = Join-Path $env:TEMP ("cc-session-job-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$pidFile = Join-Path $tmpDir 'child.pid'
$ownerScript = Join-Path $tmpDir 'owner.ps1'
$gitModePath = Get-ClientFile 'git-mode.ps1'
$ownerBody = @"
`$ErrorActionPreference = 'Stop'
function Get-FunctionSource {
    param([string]`$Content, [string]`$Name)
    `$m = [regex]::Match(`$Content, "function\s+`$Name\b")
    if (-not `$m.Success) { throw "missing `$Name" }
    `$start = `$m.Index
    `$i = `$Content.IndexOf('{', `$start)
    `$depth = 0
    for (`$j = `$i; `$j -lt `$Content.Length; `$j++) {
        if (`$Content[`$j] -eq '{') { `$depth++ }
        elseif (`$Content[`$j] -eq '}') {
            `$depth--
            if (`$depth -eq 0) { return `$Content.Substring(`$start, `$j - `$start + 1) }
        }
    }
    throw "unbalanced `$Name"
}
`$raw = Get-Content -LiteralPath '$($gitModePath -replace "'", "''")' -Raw
foreach (`$n in @('Initialize-ConnectSessionJob', 'Add-ConnectSessionJobProcess', 'Stop-ConnectSessionJob', 'Start-JobBoundProcess')) {
    . ([scriptblock]::Create((Get-FunctionSource -Content `$raw -Name `$n)))
}
`$child = Start-JobBoundProcess -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 120'
) -WindowStyle Hidden -PassThru
if (-not `$child) { throw 'Start-JobBoundProcess returned null' }
Set-Content -LiteralPath '$($pidFile -replace "'", "''")' -Value ([string]`$child.Id) -Encoding ASCII
# Exit immediately with the session job handle still open in THIS process only.
# Windows closes that handle on process exit => KILL_ON_JOB_CLOSE terminates `$child.
exit 0
"@
try {
    Set-Content -LiteralPath $ownerScript -Value $ownerBody -Encoding UTF8
    $owner = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ownerScript
    ) -WindowStyle Hidden -PassThru
    if (-not $owner.WaitForExit(20000)) {
        try { $owner.Kill() } catch {}
        Assert $false 'B: owner process exited within 20s'
    } else {
        Assert ($owner.ExitCode -eq 0) ("B: owner process exited cleanly (exit={0})" -f $owner.ExitCode)
    }

    $deadline = (Get-Date).AddSeconds(5)
    $childPid = $null
    while ((Get-Date) -lt $deadline -and -not $childPid) {
        if (Test-Path -LiteralPath $pidFile) {
            $rawPid = (Get-Content -LiteralPath $pidFile -TotalCount 1 -ErrorAction SilentlyContinue)
            if ($rawPid -match '^\d+$') { $childPid = [int]$rawPid }
        }
        Start-Sleep -Milliseconds 100
    }
    Assert ($null -ne $childPid) 'B: owner wrote grandchild PID before exiting'

    $dead = $false
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        if ($null -eq $childPid) { break }
        $alive = Get-Process -Id $childPid -ErrorAction SilentlyContinue
        if (-not $alive) { $dead = $true; break }
        Start-Sleep -Milliseconds 200
    }
    Assert $dead ("B: grandchild pid={0} was killed when its owner process exited (real job-object parent-death cleanup)" -f $childPid)
    if (-not $dead -and $childPid) {
        try { Stop-Process -Id $childPid -Force -ErrorAction SilentlyContinue } catch {}
    }
} finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
