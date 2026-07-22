Set-Location 'D:\Smart\Claude-Code-Server'
$tests = @(
  'scripts\client\tests\test-hard-multi-agent-regressions.ps1',
  'scripts\client\tests\test-log-sync-contracts.ps1',
  'scripts\client\tests\test-session-log-contracts.ps1',
  'scripts\client\tests\test-editor-launch-strategies.ps1',
  'scripts\client\tests\verify-perf-gates.ps1',
  'scripts\client\tests\test-publish.ps1'
)
$summary = @()
foreach ($t in $tests) {
  Write-Host ("==== RUN $t ====")
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $t 2>&1 | Out-String
  $code = $LASTEXITCODE
  $sw.Stop()
  # print last 40 lines only to keep output small
  ($out -split "`n" | Select-Object -Last 40) -join "`n" | Write-Host
  Write-Host ("EXIT=$code MS=$($sw.ElapsedMilliseconds)")
  $summary += [pscustomobject]@{ Test = $t; Exit = $code; Ms = $sw.ElapsedMilliseconds }
}
Write-Host '==== SUMMARY2 ===='
foreach ($r in $summary) {
  $st = if ($r.Exit -eq 0) { 'PASS' } else { 'FAIL' }
  Write-Host ("$st | exit=$($r.Exit) | ms=$($r.Ms) | $($r.Test)")
}
# Version drift
Write-Host '==== VERSION DRIFT ===='
$wv = (Get-Content 'scripts\client\windows\connect-version.txt' -Raw).Trim()
$mv = if (Test-Path 'scripts\client\mac\connect-version.txt') { (Get-Content 'scripts\client\mac\connect-version.txt' -Raw).Trim() } else { 'MISSING' }
$ps = Select-String -Path 'scripts\client\windows\connect.ps1' -Pattern "ConnectVersion = '([^']+)'" | Select-Object -First 1
$sh = Select-String -Path 'scripts\client\mac\connect.sh' -Pattern "CONNECT_VERSION='([^']+)'" | Select-Object -First 1
Write-Host ("windows/connect-version.txt=$wv")
Write-Host ("mac/connect-version.txt=$mv")
Write-Host ("connect.ps1=$($ps.Matches[0].Groups[1].Value)")
Write-Host ("connect.sh=$($sh.Matches[0].Groups[1].Value)")
# Feature markers
Write-Host '==== FEATURE MARKERS ===='
$files = @('scripts\client\windows\connect-update.ps1','scripts\client\connect-ui.ps1','scripts\client\windows\connect.ps1','scripts\client\git-mode.ps1')
foreach ($pat in @('update-policy','update-defer','\(mounted\)','ConnectQuiet','CLAUDE_CONNECT_VERBOSE','SkipIfHealthy','already mounted')) {
  $hit = $false
  foreach ($f in $files) {
    if (Select-String -Path $f -Pattern $pat -Quiet -SimpleMatch:($pat -notmatch '\\')) { $hit = $true; break }
    if (Select-String -Path $f -Pattern $pat -Quiet) { $hit = $true; break }
  }
  Write-Host ("MARKER $($pat): $(if($hit){'PRESENT'}else{'ABSENT'})")
}
