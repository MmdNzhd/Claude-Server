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
    @{ Name = 'connect-hygiene-menu'; Script = 'test-connect-hygiene-menu.ps1' }
    @{ Name = 'connect-hygiene-complete'; Script = 'test-connect-hygiene-complete.ps1' }
    @{ Name = 'connect-preflight-skip-heal'; Script = 'test-connect-preflight-skip-heal.ps1' }
    @{ Name = 'connect-preflight-skip-update'; Script = 'test-connect-preflight-skip-update.ps1' }
    @{ Name = 'connect-task7-prefetch-foreign-cache'; Script = 'test-connect-task7-prefetch-foreign-cache.ps1' }
    @{ Name = 'connect-task8-deferred-setup'; Script = 'test-connect-task8-deferred-setup.ps1' }
    @{ Name = 'wait-deferred-server-setup-timeout-live'; Script = 'test-wait-deferred-server-setup-timeout-live.ps1' }
    @{ Name = 'empty-menu-manual-update'; Script = 'test-empty-menu-manual-update.ps1' }
    @{ Name = 'run-id-multi-ui'; Script = 'test-run-id-multi-ui.ps1' }
    @{ Name = 'connect-update-script-only-drift'; Script = 'test-connect-update-script-only-drift.ps1' }
    @{ Name = 'baseline-connect-working-invariants'; Script = 'test-baseline-connect-working-invariants.ps1' }
    @{ Name = 'ssh-user-fix-retry';  Script = 'test-ssh-user-fix-retry.ps1' }
    @{ Name = 'ssh-config-multi-writer-hard'; Script = 'test-ssh-config-multi-writer-hard.ps1' }
    @{ Name = 'connect-auth-key-install-hard'; Script = 'test-connect-auth-key-install-hard.ps1' }
    @{ Name = 'auth-stamp-skip';      Script = 'test-auth-stamp-skip.ps1' }
    @{ Name = 'auth-stamp-prefetch-no-block'; Script = 'test-auth-stamp-prefetch-no-block.ps1' }
    @{ Name = 'laptop-ssh-ready';     Script = 'test-laptop-ssh-ready.ps1' }
    @{ Name = 'git-mode-deep';        Script = 'test-git-mode-deep.ps1' }
    @{ Name = 'cursor-proxy-lifetime'; Script = 'test-cursor-proxy-lifetime.ps1' }
    @{ Name = 'mac-proxy-release-on-clear'; Script = 'test-mac-proxy-release-on-clear.ps1' }
    @{ Name = 'designer-close-log'; Script = 'test-designer-close-log.ps1' }
    @{ Name = 'editor-launch';        Script = 'test-editor-launch.ps1' }
    @{ Name = 'dead-safe-delete-connect'; Script = 'test-dead-safe-delete-connect.ps1' }
    @{ Name = 'editor-launch-strategies'; Script = 'test-editor-launch-strategies.ps1' }
    @{ Name = 'folder-uri-equals-arg-live'; Script = 'test-folder-uri-equals-arg-live.ps1' }
    @{ Name = 'connect-diagnostic';     Script = 'test-connect-diagnostic.ps1' }
    @{ Name = 'mounts-cache';           Script = 'test-mounts-cache.ps1' }
    @{ Name = 'xray-probe-cache';       Script = 'test-xray-probe-cache.ps1' }
    @{ Name = 'pushconf-tcp-gate';      Script = 'test-pushconf-tcp-gate.ps1' }
    @{ Name = 'server-setup-step-progress'; Script = 'test-server-setup-step-progress.ps1' }
    @{ Name = 'tunnel-tcp-state-cache'; Script = 'test-tunnel-tcp-state-cache.ps1' }
    @{ Name = 'xray-http-leg-resilience'; Script = 'test-xray-http-leg-resilience.ps1' }
    @{ Name = 'xray-socks-leg-resilience'; Script = 'test-xray-socks-leg-resilience.ps1' }
    @{ Name = 'launch-fresh-project-windows-open'; Script = 'test-launch-fresh-project-windows-open.ps1' }
    @{ Name = 'title-project-match';    Script = 'test-title-project-match.ps1' }
    @{ Name = 'agent-home-launch-gate'; Script = 'test-agent-home-launch-gate.ps1' }
    @{ Name = 'launch-success-confirm-unify'; Script = 'test-launch-success-confirm-unify.ps1' }
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
    @{ Name = 'log-sync-mkdir-no-find-on-fast-path'; Script = 'test-log-sync-mkdir-no-find-on-fast-path.ps1' }
    @{ Name = 'log-sync-nullsafe';      Script = 'test-log-sync-nullsafe.ps1' }
    @{ Name = 'log-sync-chunk-read-nullsafe'; Script = 'test-log-sync-chunk-read-nullsafe.ps1' }
    @{ Name = 'log-sync-delivery-nonerror'; Script = 'test-log-sync-delivery-nonerror.ps1' }
    @{ Name = 'log-sync-ack-no-feedback-loop'; Script = 'test-log-sync-ack-no-feedback-loop.ps1' }
    @{ Name = 'error-flush-contract';   Script = 'test-error-flush-contract.ps1' }
    @{ Name = 'mount-failfast'; Script = 'test-mount-failfast.ps1' }
    @{ Name = 'session-fresh-probe-skips'; Script = 'test-session-fresh-probe-skips.ps1' }
    @{ Name = 'session-fresh-probe-skips-deep'; Script = 'test-session-fresh-probe-skips-deep.ps1' }
    @{ Name = 'session-fresh-ttl-matrix'; Script = 'test-session-fresh-ttl-matrix.ps1' }
    @{ Name = 'mount-check-skipped-on-bg-up'; Script = 'test-mount-check-skipped-on-bg-up.ps1' }
    @{ Name = 'mount-hash-seed-from-setup'; Script = 'test-mount-hash-seed-from-setup.ps1' }
    @{ Name = 'elevate-when-needed'; Script = 'test-elevate-when-needed.ps1' }
    @{ Name = 'save-connect-conf-key'; Script = 'test-save-connect-conf-key.ps1' }
    @{ Name = 'hard-connect-ux-20260723'; Script = 'test-hard-connect-ux-20260723.ps1' }
    @{ Name = 'hard-multi-agent-regressions'; Script = 'test-hard-multi-agent-regressions.ps1' }
    @{ Name = 'multi-agent-boot-slots-live'; Script = 'test-multi-agent-boot-slots-live.ps1' }
    @{ Name = 'multi-agent-deferred-slot-live'; Script = 'test-multi-agent-deferred-slot-live.ps1' }
    @{ Name = 'multi-agent-promote-shared-dir-live'; Script = 'test-multi-agent-promote-shared-dir-live.ps1' }
    # Domain hard-batch suites (~14 Assert each; multi-agent coverage raise 2026-07-27)
    @{ Name = 'git-tunnel-hard-batch'; Script = 'test-git-tunnel-hard-batch.ps1' }
    @{ Name = 'mac-connect-hard-batch'; Script = 'test-mac-connect-hard-batch.ps1' }
    @{ Name = 'designer-connect-hard-batch'; Script = 'test-designer-connect-hard-batch.ps1' }
    @{ Name = 'mount-active-hard-batch'; Script = 'test-mount-active-hard-batch.ps1' }
    @{ Name = 'windows-mcp-hard-batch'; Script = 'test-windows-mcp-hard-batch.ps1' }
    @{ Name = 'hard-utf8-mojibake-fleet'; Script = 'test-hard-utf8-mojibake-fleet.ps1' }
    @{ Name = 'sidecar-xray-hard-batch'; Script = 'test-sidecar-xray-hard-batch.ps1' }
    @{ Name = 'editor-auth-hard-batch'; Script = 'test-editor-auth-hard-batch.ps1' }
    @{ Name = 'tunnel-proxy-skip-hard'; Script = 'test-tunnel-proxy-skip-hard.ps1' }
    @{ Name = 'tunnel-proxy-skip-harder'; Script = 'test-tunnel-proxy-skip-harder.ps1' }
    @{ Name = 'logging-runid-hard-batch'; Script = 'test-logging-runid-hard-batch.ps1' }
    @{ Name = 'bat-preflight-heal-hard-batch'; Script = 'test-bat-preflight-heal-hard-batch.ps1' }
    @{ Name = 'connect-heal-downloads-stale'; Script = 'test-connect-heal-downloads-stale.ps1' }
    @{ Name = 'publish-iexpress-hard-batch'; Script = 'test-publish-iexpress-hard-batch.ps1' }
    @{ Name = 'elevate-ssh-hard-batch'; Script = 'test-elevate-ssh-hard-batch.ps1' }
    @{ Name = 'update-relaunch-hard-batch'; Script = 'test-update-relaunch-hard-batch.ps1' }
    @{ Name = 'versioned-layout-extra-hard-batch'; Script = 'test-versioned-layout-extra-hard-batch.ps1' }
    @{ Name = 'connect-ui-menu-hard-batch'; Script = 'test-connect-ui-menu-hard-batch.ps1' }
    @{ Name = 'server-laptop-exec-hard-batch'; Script = 'test-server-laptop-exec-hard-batch.ps1' }
    @{ Name = 'diagnostic-scorecard-hard-batch'; Script = 'test-diagnostic-scorecard-hard-batch.ps1' }
    # HARDER LIVE multi-agent suites (2026-07-27) — sequential; do not soften fails by editing prod
    @{ Name = 'harder-live-bat-boot-handoff'; Script = 'test-harder-live-bat-boot-handoff.ps1' }
    @{ Name = 'harder-live-daylog-hammer'; Script = 'test-harder-live-daylog-hammer.ps1' }
    @{ Name = 'harder-live-deferred-slot'; Script = 'test-harder-live-deferred-slot.ps1' }
    @{ Name = 'harder-live-deferred-server-setup-timeout'; Script = 'test-harder-live-deferred-server-setup-timeout.ps1' }
    @{ Name = 'harder-live-editor-launch'; Script = 'test-harder-live-editor-launch.ps1' }
    @{ Name = 'harder-live-elevate-adminak'; Script = 'test-harder-live-elevate-adminak.ps1' }
    @{ Name = 'harder-live-exe-atomic-swap'; Script = 'test-harder-live-exe-atomic-swap.ps1' }
    @{ Name = 'harder-live-hygiene-race'; Script = 'test-harder-live-hygiene-race.ps1' }
    @{ Name = 'harder-live-instant-launcher'; Script = 'test-harder-live-instant-launcher.ps1' }
    @{ Name = 'harder-live-console-hide-storm'; Script = 'test-harder-live-console-hide-storm.ps1' }
    # Slow windows-mcp LIVE suites (storm/chaos/brutal): many minutes; stall publish\deploy.bat.
    # Run directly (e.g. powershell -File test-brutal-live-windows-mcp-abuse.ps1) when editing
    # windows-mcp-laptop.ps1. Deploy gate also lists them in $SkipDeployScripts.
    # @{ Name = 'harder-live-windows-mcp-storm'; Script = 'test-harder-live-windows-mcp-storm.ps1' }
    # @{ Name = 'hardest-live-windows-mcp-chaos'; Script = 'test-hardest-live-windows-mcp-chaos.ps1' }
    # @{ Name = 'brutal-live-windows-mcp-abuse'; Script = 'test-brutal-live-windows-mcp-abuse.ps1' }
    @{ Name = 'harder-live-log-flush'; Script = 'test-harder-live-log-flush.ps1' }
    @{ Name = 'harder-live-mount-active'; Script = 'test-harder-live-mount-active.ps1' }
    @{ Name = 'harder-live-orphan-tunnel'; Script = 'test-harder-live-orphan-tunnel.ps1' }
    @{ Name = 'harder-live-promote-race'; Script = 'test-harder-live-promote-race.ps1' }
    @{ Name = 'harder-live-runid-bat'; Script = 'test-harder-live-runid-bat.ps1' }
    @{ Name = 'harder-live-sidecar-backend'; Script = 'test-harder-live-sidecar-backend.ps1' }
    @{ Name = 'harder-live-slot-storm'; Script = 'test-harder-live-slot-storm.ps1' }
    @{ Name = 'harder-live-update-filelock'; Script = 'test-harder-live-update-filelock.ps1' }
    @{ Name = 'harder-live-versioned-prune'; Script = 'test-harder-live-versioned-prune.ps1' }
    @{ Name = 'hard-cmd-flash-fleet-push'; Script = 'test-hard-cmd-flash-fleet-push.ps1' }
    @{ Name = 'p0-connect-fixes'; Script = 'test-p0-connect-fixes.ps1' }
    @{ Name = 'windows-mcp-no-orphan-cmd'; Script = 'test-windows-mcp-no-orphan-cmd.ps1' }
    @{ Name = 'windows-mcp-ports'; Script = 'test-windows-mcp-ports.ps1' }
    @{ Name = 'figma-skills-pack'; Script = 'test-figma-skills-pack.ps1' }
    @{ Name = 'connect-bat-max-ps-starts'; Script = 'test-connect-bat-max-ps-starts.ps1' }
    @{ Name = 'client-update-policy-optional'; Script = 'test-client-update-policy-optional.ps1' }
    @{ Name = 'smartscreen-docs-contract'; Script = 'test-smartscreen-docs-contract.ps1' }
    @{ Name = 'never-again-ship-gates'; Script = 'test-never-again-ship-gates.ps1' }
    @{ Name = 'bundle-deploy-cohesion'; Script = 'test-bundle-deploy-cohesion.ps1' }
    @{ Name = 'harder-adversarial'; Script = 'test-harder-adversarial.ps1' }
    @{ Name = 'versioned-layout'; Script = 'test-versioned-layout.ps1' }
    @{ Name = 'boot-flat-migrate-live'; Script = 'test-boot-flat-migrate-live.ps1' }
    @{ Name = 'flat-update-creates-verdir-live'; Script = 'test-flat-update-creates-verdir-live.ps1' }
    @{ Name = 'versioned-layout-deep-live'; Script = 'test-versioned-layout-deep-live.ps1' }
    @{ Name = 'versioned-layout-hard-regressions'; Script = 'test-versioned-layout-hard-regressions.ps1' }
    @{ Name = 'versioned-layout-harder-adversarial'; Script = 'test-versioned-layout-harder-adversarial.ps1' }
    @{ Name = 'exe-launch-slot-gate'; Script = 'test-exe-launch-slot-gate.ps1' }
    @{ Name = 'exe-spaced-path-launch'; Script = 'test-exe-spaced-path-launch.ps1' }
    @{ Name = 'cursor-profile-db-tool'; Script = 'test-cursor-profile-db-tool.ps1' }
    @{ Name = 'chat-freeze-skip-paths'; Script = 'test-chat-freeze-skip-paths.ps1' }
    @{ Name = 'banner-probe-interval'; Script = 'test-banner-probe-interval.ps1' }
    @{ Name = 'sidecar-watchdog-lease'; Script = 'test-sidecar-watchdog-lease.ps1' }
    @{ Name = 'pushconf-am-only'; Script = 'test-pushconf-am-only.ps1' }
    @{ Name = 'pushconf-primary-liveness'; Script = 'test-pushconf-primary-liveness.ps1' }
    @{ Name = 'agent-path-diag-logs'; Script = 'test-agent-path-diag-logs.ps1' }
    @{ Name = 'connect-scorecard'; Script = 'test-connect-scorecard.ps1' }
    @{ Name = 'editor-opened-script-scope'; Script = 'test-editor-opened-script-scope.ps1' }
    @{ Name = 'launch-trust-path-no-double-relaunch'; Script = 'test-launch-trust-path-no-double-relaunch.ps1' }
    @{ Name = 'opening-fail-clears-editor-seen'; Script = 'test-opening-fail-clears-editor-seen.ps1' }
    @{ Name = 'sidecar-job-object'; Script = 'test-sidecar-job-object.ps1' }
    @{ Name = 'sidecar-front-flap'; Script = 'test-sidecar-front-flap.ps1' }
    @{ Name = 'connect-update-bundle-primary'; Script = 'test-connect-update-bundle-primary.ps1' }
    @{ Name = 'windows-shadow-canon'; Script = 'test-windows-shadow-canon.ps1' }
    @{ Name = 'skip-12-fingerprint-hold'; Script = 'test-skip-12-fingerprint-hold.ps1' }
    @{ Name = 'step-console-quiet'; Script = 'test-step-console-quiet.ps1' }
    @{ Name = 'cursor-launch-console-detached'; Script = 'test-cursor-launch-console-detached.ps1' }
    @{ Name = 'tunnel-job-object'; Script = 'test-tunnel-job-object.ps1' }
    @{ Name = 'tunnel-job-object-live'; Script = 'test-tunnel-job-object-live.ps1' }
    @{ Name = 'session-job-bound-process-live'; Script = 'test-session-job-bound-process-live.ps1' }
    @{ Name = 'sshx-hard-kill'; Script = 'test-sshx-hard-kill.ps1' }
    @{ Name = 'sshx-hard-kill-live'; Script = 'test-sshx-hard-kill-live.ps1' }
    @{ Name = 'update-check-failfast'; Script = 'test-update-check-failfast.ps1' }
    @{ Name = 'update-check-failfast-live'; Script = 'test-update-check-failfast-live.ps1' }
    @{ Name = 'logsync-fast-timeout'; Script = 'test-logsync-fast-timeout.ps1' }
    @{ Name = 'logsync-fast-timeout-live'; Script = 'test-logsync-fast-timeout-live.ps1' }
    @{ Name = 'exe-atomic-swap'; Script = 'test-exe-atomic-swap.ps1' }
    @{ Name = 'exe-atomic-swap-live'; Script = 'test-exe-atomic-swap-live.ps1' }
    @{ Name = 'exe-promote-launch-dir-hard'; Script = 'test-exe-promote-launch-dir-hard.ps1' }
    @{ Name = 'exe-promote-dirs-contract'; Script = 'test-exe-promote-dirs-contract.ps1' }
    @{ Name = 'update-no-defer-prompt'; Script = 'test-update-no-defer-prompt.ps1' }
    @{ Name = 'update-kill-self-contract'; Script = 'test-update-kill-self-contract.ps1' }
    @{ Name = 'update-relaunch-no-press-enter-live'; Script = 'test-update-relaunch-no-press-enter-live.ps1' }
    @{ Name = 'local-port-free-bind-live'; Script = 'test-local-port-free-bind-live.ps1' }
    @{ Name = 'orphan-tunnel-kill-vs-sibling-live'; Script = 'test-orphan-tunnel-kill-vs-sibling-live.ps1' }
    @{ Name = 'connect-hygiene-soft-vs-sibling-live'; Script = 'test-connect-hygiene-soft-vs-sibling-live.ps1' }
    @{ Name = 'auth-stamp-current-live'; Script = 'test-auth-stamp-current-live.ps1' }
    @{ Name = 'auth-golden-missing-cache-live'; Script = 'test-auth-golden-missing-cache-live.ps1' }
    @{ Name = 'sidecar-listening-live'; Script = 'test-sidecar-listening-live.ps1' }
    @{ Name = 'tcp-port-relay-live'; Script = 'test-tcp-port-relay-live.ps1' }
    @{ Name = 'sidecar-boot-reap-live'; Script = 'test-sidecar-boot-reap-live.ps1' }
    @{ Name = 'sidecar-boot-reap-preserve-fronts-live'; Script = 'test-sidecar-boot-reap-preserve-fronts-live.ps1' }
    @{ Name = 'remote-editor-detect-live'; Script = 'test-remote-editor-detect-live.ps1' }
    @{ Name = 'connect-single-instance-live'; Script = 'test-connect-single-instance-live.ps1' }
    @{ Name = 'mount-port-fallback-live'; Script = 'test-mount-port-fallback-live.ps1' }
    @{ Name = 'window-title-site-tag-live'; Script = 'test-window-title-site-tag-live.ps1' }
    @{ Name = 'xray-probe-worst-case-live'; Script = 'test-xray-probe-worst-case-live.ps1' }
    @{ Name = 'job-detach-survives-close-live'; Script = 'test-job-detach-survives-close-live.ps1' }
    @{ Name = 'concurrent-log-writers-live'; Script = 'test-concurrent-log-writers-live.ps1' }
    @{ Name = 'known-down-selfheal-live'; Script = 'test-known-down-selfheal-live.ps1' }
    @{ Name = 'launch-recovery-reachable-live'; Script = 'test-launch-recovery-reachable-live.ps1' }
    @{ Name = 'window-kill-staleness-live'; Script = 'test-window-kill-staleness-live.ps1' }
    @{ Name = 'window-foreground-live'; Script = 'test-window-foreground-live.ps1' }
    @{ Name = 'context-log-sync-noninline-live'; Script = 'test-context-log-sync-noninline-live.ps1' }
    @{ Name = 'server-setup-round-trip-merge-live'; Script = 'test-server-setup-round-trip-merge-live.ps1' }
    @{ Name = 'setup-debounce-bounded-live'; Script = 'test-setup-debounce-bounded-live.ps1' }
    @{ Name = 'console-declutter-warnings'; Script = 'test-console-declutter-warnings.ps1' }
    @{ Name = 'mount-backgrounded-live'; Script = 'test-mount-backgrounded-live.ps1' }
    @{ Name = 'mount-bg-daylog-mutex-contention-live'; Script = 'test-mount-bg-daylog-mutex-contention-live.ps1' }
    @{ Name = 'tunnel-sync-down-debounce-returns-true'; Script = 'test-tunnel-sync-down-debounce-returns-true.ps1' }
    @{ Name = 'tunnel-no-proc-keepalive'; Script = 'test-tunnel-no-proc-keepalive.ps1' }
    # Zombie-owner / reseed Gap suites (2026-07-29 plan Tasks 1-7)
    @{ Name = 'reseed-canbindl-gate'; Script = 'test-reseed-canbindl-gate.ps1' }
    @{ Name = 'wait-local-r-ownership'; Script = 'test-wait-local-r-ownership.ps1' }
    @{ Name = 'stale-forward-wait-init'; Script = 'test-stale-forward-wait-init.ps1' }
    @{ Name = 'stale-forward-rebind-streak'; Script = 'test-stale-forward-rebind-streak.ps1' }
    @{ Name = 'tunnel-banner-transport'; Script = 'test-tunnel-banner-transport.ps1' }
    @{ Name = 'tunnel-wait-backoff-fanout'; Script = 'test-tunnel-wait-backoff-fanout.ps1' }
    @{ Name = 'proxy-owner-service-coupling'; Script = 'test-proxy-owner-service-coupling.ps1' }
    @{ Name = 'local-tunnel-ssh-pids'; Script = 'test-local-tunnel-ssh-pids.ps1' }
    @{ Name = 'incident-gap-replay-contract'; Script = 'test-incident-gap-replay-contract.ps1' }
    @{ Name = 'incident-gap-replay-harness'; Script = 'test-incident-gap-replay-harness.ps1' }
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

