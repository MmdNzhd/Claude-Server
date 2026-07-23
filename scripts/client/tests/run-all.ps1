#Requires -Version 5.1
# run-all.ps1 - run all client regression / audit scripts
$ErrorActionPreference = 'Stop'
$TestsDir = $PSScriptRoot

$suites = @(
    @{ Name = 'pipeline-deep';      Script = 'test-pipeline-deep.ps1' }
    @{ Name = 'pipeline-repro';       Script = 'test-pipeline-repro.ps1' }
    @{ Name = 'connect-ui';           Script = 'test-connect-ui.ps1' }
    @{ Name = 'select-project';       Script = 'test-select-project.ps1' }
    @{ Name = 'connect-pipeline';     Script = 'test-connect-pipeline.ps1' }
    @{ Name = 'ssh-user-fix-retry';  Script = 'test-ssh-user-fix-retry.ps1' }
    @{ Name = 'auth-stamp-skip';      Script = 'test-auth-stamp-skip.ps1' }
    @{ Name = 'laptop-ssh-ready';     Script = 'test-laptop-ssh-ready.ps1' }
    @{ Name = 'git-mode-deep';        Script = 'test-git-mode-deep.ps1' }
    @{ Name = 'cursor-proxy-lifetime'; Script = 'test-cursor-proxy-lifetime.ps1' }
    @{ Name = 'editor-launch';        Script = 'test-editor-launch.ps1' }
    @{ Name = 'editor-launch-strategies'; Script = 'test-editor-launch-strategies.ps1' }
    @{ Name = 'connect-diagnostic';     Script = 'test-connect-diagnostic.ps1' }
    @{ Name = 'parse-connect-perf';     Script = 'test-parse-connect-perf.ps1' }
    @{ Name = 'verify-perf-gates';      Script = 'test-verify-perf-gates.ps1' }
    @{ Name = 'launch-perf-live';       Script = 'test-launch-perf-live.ps1' }
    @{ Name = 'cursor-auth-merge';    Script = 'test-cursor-auth-merge.ps1' }
    @{ Name = 'publish';              Script = 'test-publish.ps1' }
    @{ Name = 'ssh-remote-bash-lf'; Script = 'test-ssh-remote-bash-lf-only.ps1' }
    @{ Name = 'acquire-no-port-alias'; Script = 'test-acquire-tunnel-port-no-port-alias.ps1' }
    @{ Name = 'push-conf-script-port'; Script = 'test-push-conf-uses-script-port.ps1' }
    @{ Name = 'foreign-no-port-mutation'; Script = 'test-foreign-peer-no-global-port-mutation.ps1' }
    @{ Name = 'foreign-own-block'; Script = 'test-foreign-own-block-indeterminate.ps1' }
    @{ Name = 'orphan-skip-sibling'; Script = 'test-orphan-tunnel-skip-sibling.ps1' }
    @{ Name = 'recovery-skip-clear'; Script = 'test-auto-recovery-skip-clear-mount-matrix.ps1' }
    @{ Name = 'presence-recovery-parity'; Script = 'test-editor-presence-recovery-parity.ps1' }
    @{ Name = 'mount-ok-reassert'; Script = 'test-mount-ok-reassert-before-recovery-end.ps1' }
    @{ Name = 'active-mount-guard'; Script = 'test-active-mount-guard.ps1' }
    @{ Name = 'pushconf-quoting';     Script = 'test-pushconf-quoting.ps1' }
    @{ Name = 'connect-update-fail-exit'; Script = 'test-connect-update-fail-exit.ps1' }
    @{ Name = 'session-log-contracts'; Script = 'test-session-log-contracts.ps1' }
    @{ Name = 'log-sync-contracts';     Script = 'test-log-sync-contracts.ps1' }
    @{ Name = 'log-sync-forbid-shrink'; Script = 'test-log-sync-forbid-shrink.ps1' }
    @{ Name = 'error-flush-contract';   Script = 'test-error-flush-contract.ps1' }
    @{ Name = 'mount-failfast'; Script = 'test-mount-failfast.ps1' }
    @{ Name = 'elevate-when-needed'; Script = 'test-elevate-when-needed.ps1' }
    @{ Name = 'save-connect-conf-key'; Script = 'test-save-connect-conf-key.ps1' }
    @{ Name = 'hard-connect-ux-20260723'; Script = 'test-hard-connect-ux-20260723.ps1' }
    @{ Name = 'hard-multi-agent-regressions'; Script = 'test-hard-multi-agent-regressions.ps1' }
    @{ Name = 'p0-connect-fixes'; Script = 'test-p0-connect-fixes.ps1' }
    @{ Name = 'windows-mcp-no-orphan-cmd'; Script = 'test-windows-mcp-no-orphan-cmd.ps1' }
    @{ Name = 'connect-bat-max-ps-starts'; Script = 'test-connect-bat-max-ps-starts.ps1' }
    @{ Name = 'client-update-policy-optional'; Script = 'test-client-update-policy-optional.ps1' }
    @{ Name = 'smartscreen-docs-contract'; Script = 'test-smartscreen-docs-contract.ps1' }
    @{ Name = 'exe-launch-slot-gate'; Script = 'test-exe-launch-slot-gate.ps1' }
    @{ Name = 'cursor-profile-db-tool'; Script = 'test-cursor-profile-db-tool.ps1' }
    @{ Name = 'chat-freeze-skip-paths'; Script = 'test-chat-freeze-skip-paths.ps1' }
    @{ Name = 'banner-probe-interval'; Script = 'test-banner-probe-interval.ps1' }
    @{ Name = 'sidecar-watchdog-lease'; Script = 'test-sidecar-watchdog-lease.ps1' }
    @{ Name = 'pushconf-am-only'; Script = 'test-pushconf-am-only.ps1' }
    @{ Name = 'connect-scorecard'; Script = 'test-connect-scorecard.ps1' }
    @{ Name = 'sidecar-job-object'; Script = 'test-sidecar-job-object.ps1' }
    @{ Name = 'windows-shadow-canon'; Script = 'test-windows-shadow-canon.ps1' }
    @{ Name = 'skip-12-fingerprint-hold'; Script = 'test-skip-12-fingerprint-hold.ps1' }
    @{ Name = 'step-console-quiet'; Script = 'test-step-console-quiet.ps1' }
)

$fail = 0
Write-Host ""
Write-Host "=== Client tests ($TestsDir) ===" -ForegroundColor White
Write-Host ""

foreach ($suite in $suites) {
    $path = Join-Path $TestsDir $suite.Script
    Write-Host "--- $($suite.Name) ---" -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $path
    if ($LASTEXITCODE -ne 0) { $fail++ }
    Write-Host ""
}

Write-Host "--- audit-local-connect ---" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $TestsDir 'audit-local-connect.ps1')
# audit exits 1 when broken copies exist on disk (expected on dev machines with old Desktop copies)
if ($LASTEXITCODE -ne 0) {
    Write-Host "  (audit reported non-SAFE copies - see output above)" -ForegroundColor DarkYellow
}
Write-Host ""

if ($fail -eq 0) {
    Write-Host "All test suites passed." -ForegroundColor Green
    exit 0
}
Write-Host "$fail test suite(s) failed." -ForegroundColor Red
exit 1

