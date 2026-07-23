$ErrorActionPreference = 'Stop'
foreach ($f in @(
  'test-ssh-remote-bash-lf-only.ps1',
  'test-auto-recovery-skip-clear-mount-matrix.ps1',
  'test-mount-ok-reassert-before-recovery-end.ps1',
  'test-windows-mcp-no-orphan-cmd.ps1',
  'test-chat-freeze-skip-paths.ps1',
  'test-client-update-policy-optional.ps1',
  'test-editor-presence-recovery-parity.ps1'
)) {
  Write-Host ("==== FILE $f ====")
  Get-Content (Join-Path 'scripts/client/tests' $f) | ForEach-Object { $_ }
  Write-Host ''
}
