$ErrorActionPreference='Continue'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))
$tests = @(
  'scripts/client/tests/test-hard-multi-agent-regressions.ps1',
  'scripts/client/tests/test-session-log-contracts.ps1',
  'scripts/client/tests/test-connect-pipeline.ps1',
  'scripts/client/tests/test-editor-launch.ps1',
  'scripts/client/tests/test-editor-launch-strategies.ps1',
  'scripts/client/tests/test-pushconf-quoting.ps1',
  'scripts/client/tests/test-git-mode-deep.ps1',
  'scripts/client/tests/test-cursor-auth-merge.ps1',
  'scripts/client/tests/test-connect-ui.ps1'
)
$results = @()
foreach ($t in $tests) {
  Write-Host "`n########## RUNNING $t ##########" -ForegroundColor Cyan
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = & powershell -NoProfile -File $t 2>&1 | Out-String
  $code = $LASTEXITCODE
  $sw.Stop()
  $pass = ([regex]::Matches($out, 'PASS')).Count
  $fail = ([regex]::Matches($out, 'FAIL')).Count
  Write-Host $out
  Write-Host ("RESULT exit={0} ms={1} PASS_mentions={2} FAIL_mentions={3}" -f $code, $sw.ElapsedMilliseconds, $pass, $fail) -ForegroundColor $(if($code -ne 0){'Red'}else{'Green'})
  $results += [pscustomobject]@{ Test=$t; Exit=$code; Ms=$sw.ElapsedMilliseconds; PassMentions=$pass; FailMentions=$fail }
}
Write-Host "`n===== BATCH SUMMARY =====" -ForegroundColor White
$results | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($results | Where-Object { $_.Exit -ne 0 })
Write-Host ("Suites failed: {0}/{1}" -f $failed.Count, $results.Count) -ForegroundColor $(if($failed.Count){'Red'}else{'Green'})
if ($failed.Count) { exit 1 } else { exit 0 }
