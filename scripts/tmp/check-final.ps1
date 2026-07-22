Write-Host "error-flush=$(Test-Path scripts/client/tests/test-error-flush-contract.ps1)"
Write-Host "log-sync=$(Test-Path scripts/client/tests/test-log-sync-contracts.ps1)"
Select-String -Path scripts/client/tests/run-all.ps1 -Pattern 'error-flush|log-sync-contracts' | ForEach-Object { $_.Line.Trim() }
# quick run both
& powershell -NoProfile -File scripts/client/tests/test-log-sync-contracts.ps1
Write-Host "log-sync-exit=$LASTEXITCODE"
& powershell -NoProfile -File scripts/client/tests/test-error-flush-contract.ps1
Write-Host "error-flush-exit=$LASTEXITCODE"
# _perf_emit outputs
Select-String -Path scripts/server/claude-mount.sh -Pattern 'PERF_.*_MS' | ForEach-Object { $_.Line.Trim() }
