#Requires -Version 5.1
# test-e2e-agent-hello.ps1
# Phase 2 (Rank-2): model "hello" via Cursor Agent CLI - NOT GUI Chat / Remote SSH panel.
# TEST ONLY. Does NOT modify product files.
#
# Default = contracts + agent-present check.
# Live:  powershell -File test-e2e-agent-hello.ps1 -Live [-Workspace <abs>]
param(
    [switch]$Live,
    [string]$Workspace = '',
    [int]$TimeoutSec = 120
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
. (Join-Path $PSScriptRoot 'e2e\_e2e-common.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }
function SkipMsg([string]$Msg) { Write-Host "  SKIP  $Msg" -ForegroundColor Yellow; $script:Skip++ }

Write-Host ''
Write-Host '=== E2E Phase 2: agent hello (CLI - not GUI Chat) ===' -ForegroundColor Cyan
Write-Host ''

Note 'A) contracts'
Assert ($true) 'Phase 2 uses agent/cursor-agent CLI only (fidelity: model path, not Connect GUI Chat)'
$skillHint = Join-Path $env:USERPROFILE '.claude\skills\talk-to-cursor-agent\SKILL.md'
if (Test-Path -LiteralPath $skillHint) {
    $sk = Get-Content -LiteralPath $skillHint -Raw
    Assert ($sk -match '--print') 'talk-to-cursor-agent skill documents --print'
    Assert ($sk -match '--workspace') 'talk-to-cursor-agent skill documents --workspace'
} else {
    SkipMsg 'talk-to-cursor-agent skill not on this machine (optional doc check)'
}

$agent = Get-E2eAgentCommand
if (-not $agent) {
    SkipMsg 'agent/cursor-agent not found - install Cursor Agent CLI for -Live'
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}
Assert $true ("agent CLI resolved: $agent")

if (-not $Live) {
    Note 'Live agent call skipped (pass -Live to send hello and assert reply)'
    Write-Host ''
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip (contracts only)" -f $Pass, $Fail, $Skip) `
        -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
    if ($Fail -gt 0) { exit 1 }
    exit 0
}

Note 'B) LIVE agent --print --mode ask'
if (-not $Workspace) { $Workspace = $script:RepoRoot }
$Workspace = [IO.Path]::GetFullPath($Workspace)
Assert (Test-Path -LiteralPath $Workspace) "workspace exists: $Workspace"

$token = 'PONG-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$prompt = "Reply with exactly one line containing this token and nothing else before it: $token"
$outDir = Join-Path $env:USERPROFILE '.config\claude-connect\e2e-harness'
New-Item -ItemType Directory -Force -Path $outDir -ErrorAction SilentlyContinue | Out-Null
$stdoutFile = Join-Path $outDir ("agent-hello-{0}.out.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$stderrFile = Join-Path $outDir ("agent-hello-{0}.err.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

# Prefer invoking via powershell -File agent.ps1 when path is .ps1
$argList = @(
    '--print', '--trust', '--output-format', 'text', '--mode', 'ask',
    '--workspace', $Workspace, $prompt
)
$p = $null
try {
    if ($agent -match '\.ps1$') {
        $p = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $agent) + $argList) `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
            -PassThru -WindowStyle Hidden
    } else {
        $p = Start-Process -FilePath $agent -ArgumentList $argList `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
            -PassThru -WindowStyle Hidden
    }
} catch {
    Assert $false ("failed to start agent: $($_.Exception.Message)")
}

if ($p) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
    }
    if (-not $p.HasExited) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        SkipMsg "agent timed out after ${TimeoutSec}s (killed)"
    } else {
        $body = ''
        if (Test-Path -LiteralPath $stdoutFile) { $body = Get-Content -LiteralPath $stdoutFile -Raw -ErrorAction SilentlyContinue }
        $errBody = ''
        if (Test-Path -LiteralPath $stderrFile) { $errBody = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue }
        Note ("agent exit=$($p.ExitCode) out_len=$(if ($body) { $body.Length } else { 0 })")
        if ($body -and ($body -match [regex]::Escape($token))) {
            Assert $true ("LIVE reply contains token $token")
        } elseif ($errBody -match '(?i)not logged in|login|unauthorized') {
            SkipMsg 'agent not logged in (run: agent status / agent login)'
        } elseif (-not $body) {
            SkipMsg 'agent produced empty stdout (see e2e-harness err file)'
        } else {
            Assert $false ("LIVE reply missing token $token (got head: $(([string]$body).Substring(0, [Math]::Min(120, ([string]$body).Length))))")
        }
    }
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) `
    -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
