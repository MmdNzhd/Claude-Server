$TestsDir = 'scripts\client\tests'
$names = @(
  'test-connect-pipeline.ps1',
  'test-publish.ps1',
  'test-editor-launch.ps1',
  'test-editor-launch-strategies.ps1',
  'test-connect-diagnostic.ps1',
  'test-parse-connect-perf.ps1',
  'test-verify-perf-gates.ps1',
  'test-connect-ui.ps1',
  'test-select-project.ps1',
  'test-laptop-ssh-ready.ps1',
  'test-git-mode-deep.ps1',
  'test-cursor-auth-merge.ps1'
)
foreach ($n in $names) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $TestsDir $n) | Out-Null
  Write-Host ("EXIT {0} = {1}" -f $n, $LASTEXITCODE)
}
