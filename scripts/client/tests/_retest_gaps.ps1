$ErrorActionPreference = 'Continue'
$suites = @(
  'test-ssh-remote-bash-lf-only.ps1',
  'test-auto-recovery-skip-clear-mount-matrix.ps1',
  'test-editor-presence-recovery-parity.ps1',
  'test-mount-ok-reassert-before-recovery-end.ps1',
  'test-windows-mcp-no-orphan-cmd.ps1',
  'test-chat-freeze-skip-paths.ps1',
  'test-client-update-policy-optional.ps1',
  'test-connect-pipeline.ps1',
  'test-hard-multi-agent-regressions.ps1',
  'test-p0-connect-fixes.ps1',
  'test-connect-update-fail-exit.ps1'
)
$failSuites = @()
foreach ($s in $suites) {
  $out = & (Join-Path $PSScriptRoot $s) *>&1
  $ec = $LASTEXITCODE
  $summary = ($out | Where-Object { $_ -match 'Failed:|failed\.|All .*passed|Hard regressions|P0 connect|update fail-exit' } | Select-Object -Last 2) -join ' | '
  Write-Host ("{0} EXIT={1} :: {2}" -f $s, $ec, $summary)
  if ($ec -ne 0) {
    $failSuites += $s
    $out | Where-Object { $_ -match 'FAIL' } | ForEach-Object { Write-Host ("  " + $_) }
  }
}
Write-Host ("FAIL_SUITES=" + ($failSuites -join ','))
if ($failSuites.Count -gt 0) { exit 1 } else { exit 0 }
