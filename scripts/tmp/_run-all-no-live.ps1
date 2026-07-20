#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$TestsDir = Join-Path (Get-Location) 'scripts\client\tests'
$suites = @(
    @{ Name = 'pipeline-deep';      Script = 'test-pipeline-deep.ps1' },
    @{ Name = 'pipeline-repro';       Script = 'test-pipeline-repro.ps1' },
    @{ Name = 'connect-ui';           Script = 'test-connect-ui.ps1' },
    @{ Name = 'select-project';       Script = 'test-select-project.ps1' },
    @{ Name = 'connect-pipeline';     Script = 'test-connect-pipeline.ps1' },
    @{ Name = 'laptop-ssh-ready';     Script = 'test-laptop-ssh-ready.ps1' },
    @{ Name = 'git-mode-deep';        Script = 'test-git-mode-deep.ps1' },
    @{ Name = 'editor-launch';        Script = 'test-editor-launch.ps1' },
    @{ Name = 'editor-launch-strategies'; Script = 'test-editor-launch-strategies.ps1' },
    @{ Name = 'connect-diagnostic';     Script = 'test-connect-diagnostic.ps1' },
    @{ Name = 'parse-connect-perf';     Script = 'test-parse-connect-perf.ps1' },
    @{ Name = 'verify-perf-gates';      Script = 'test-verify-perf-gates.ps1' },
    # LIVE-SKIP: test-launch-perf-live.ps1 (live WMI / Cursor on folder)
    @{ Name = 'cursor-auth-merge';    Script = 'test-cursor-auth-merge.ps1' },
    @{ Name = 'publish';              Script = 'test-publish.ps1' }
)
$fail = 0
Write-Host ''
Write-Host "=== Client tests NO-LIVE ($TestsDir) ===" -ForegroundColor White
Write-Host ''
Write-Host 'LIVE-SKIP: launch-perf-live (test-launch-perf-live.ps1)' -ForegroundColor DarkYellow
Write-Host ''
foreach ($suite in $suites) {
    $path = Join-Path $TestsDir $suite.Script
    Write-Host "--- $($suite.Name) ---" -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $path
    if ($LASTEXITCODE -ne 0) { $fail++ }
    Write-Host ''
}
Write-Host '--- audit-local-connect (informational; non-SAFE copies expected) ---' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $TestsDir 'audit-local-connect.ps1')
Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All non-live test suites passed.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail test suite(s) failed." -ForegroundColor Red
exit 1
