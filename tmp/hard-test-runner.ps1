Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
Set-Location 'D:\Smart\Claude-Code-Server'
$tests = @(
  'scripts\client\tests\test-p0-connect-fixes.ps1',
  'scripts\client\tests\audit-ps5-deep.ps1',
  'scripts\client\tests\test-connect-pipeline.ps1',
  'scripts\client\tests\test-git-mode-deep.ps1',
  'scripts\client\tests\test-connect-update-hardening.ps1',
  'scripts\client\tests\test-connect-ui.ps1',
  'scripts\client\tests\test-connect-update-fail-exit.ps1',
  'scripts\client\tests\test-select-project.ps1',
  'scripts\client\tests\test-pipeline-deep.ps1',
  'scripts\client\tests\test-editor-launch.ps1',
  'scripts\client\tests\test-pushconf-quoting.ps1',
  'scripts\client\tests\test-error-flush-contract.ps1'
)
$summary = @()
foreach ($t in $tests) {
  Write-Host ("==== RUN $t ====")
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $t 2>&1 | Out-String
  $code = $LASTEXITCODE
  $sw.Stop()
  Write-Host $out
  Write-Host ("EXIT=$code MS=$($sw.ElapsedMilliseconds)")
  $summary += [pscustomobject]@{ Test = $t; Exit = $code; Ms = $sw.ElapsedMilliseconds }
}
Write-Host '==== SUMMARY ===='
foreach ($r in $summary) {
  $st = if ($r.Exit -eq 0) { 'PASS' } else { 'FAIL' }
  Write-Host ("$st | exit=$($r.Exit) | ms=$($r.Ms) | $($r.Test)")
}
$failed = @($summary | Where-Object { $_.Exit -ne 0 }).Count
exit $(if ($failed -gt 0) { 1 } else { 0 })
