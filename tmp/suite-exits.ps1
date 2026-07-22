$suites = @(
  'hard-multi-agent-regressions.ps1',
  'session-log-contracts.ps1',
  'connect-update-fail-exit.ps1',
  'audit-local-connect.ps1',
  'verify-perf-gates.ps1',
  'cursor-auth-merge.ps1'
)
$root = Join-Path $PSScriptRoot 'scripts\client\tests'
if (-not (Test-Path $root)) { $root = 'D:\Smart\Claude-Code-Server\scripts\client\tests' }
foreach ($s in $suites) {
  & (Join-Path $root $s) *> $null
  Write-Host ("{0} => {1}" -f $s, $LASTEXITCODE)
}
