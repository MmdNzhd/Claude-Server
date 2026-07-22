Set-Location D:\Smart\Claude-Code-Server
Write-Host 'designer markers:'
Select-String -Path scripts/client/users/designer/connect.sh -Pattern 'enter_connect_single_instance|SINGLE_INSTANCE' | ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }
$w=[IO.File]::ReadAllText('scripts/client/windows/connect.ps1')
$smart=0
foreach ($c in @([char]0x2014,[char]0x2013,[char]0x201C,[char]0x201D,[char]0x2018,[char]0x2019)) {
  if ($w.IndexOf($c) -ge 0) { $smart++ }
}
Write-Host ("smart_chars=$smart")
Select-String -Path scripts/client/tests/test-connect-pipeline.ps1 -Pattern 'timeout 45' | ForEach-Object { Write-Host ("PIPE:{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }

$tests = @(
  'scripts/client/tests/test-hard-multi-agent-regressions.ps1',
  'scripts/client/tests/test-connect-pipeline.ps1'
)
foreach ($t in $tests) {
  Write-Host "`n##### $t #####" -ForegroundColor Cyan
  & powershell -NoProfile -File $t
  Write-Host ("EXIT=$LASTEXITCODE") -ForegroundColor $(if($LASTEXITCODE){'Red'}else{'Green'})
}
