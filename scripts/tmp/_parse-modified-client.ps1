$ErrorActionPreference = 'Stop'
$files = @(
  'scripts/client/connect-diagnostic.ps1',
  'scripts/client/connect-ui.ps1',
  'scripts/client/cursor-auth-laptop.ps1',
  'scripts/client/editor-launch.ps1',
  'scripts/client/git-mode.ps1',
  'scripts/client/push-laptop-exec-now.ps1',
  'scripts/client/tests/test-connect-pipeline.ps1',
  'scripts/client/tests/test-cursor-auth-merge.ps1',
  'scripts/client/tests/test-editor-launch-strategies.ps1',
  'scripts/client/tests/test-git-mode-deep.ps1',
  'scripts/client/tests/test-publish.ps1',
  'scripts/client/windows/connect-diagnostic.ps1',
  'scripts/client/windows/connect-update.ps1',
  'scripts/client/windows/connect.ps1',
  'scripts/client/_check-sepidz-auth.ps1',
  'scripts/client/_deploy-sepidz-lex.ps1',
  'scripts/client/_install-bundle-now.ps1'
)
$fail = 0
$root = (Get-Location).Path
foreach ($rel in $files) {
  $path = Join-Path $root $rel
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Host "MISSING $rel"
    $fail++
    continue
  }
  $errs = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
  if (-not $errs -or $errs.Count -eq 0) {
    Write-Host "OK parse $rel"
  } else {
    Write-Host "FAIL parse $rel"
    foreach ($err in $errs) {
      Write-Host ("  L{0}: {1}" -f $err.Extent.StartLineNumber, $err.Message)
    }
    $fail++
  }
}
Write-Host "PARSE_FAIL_COUNT=$fail"
exit $fail
