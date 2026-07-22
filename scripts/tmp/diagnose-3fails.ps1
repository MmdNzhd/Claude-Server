Set-Location D:\Smart\Claude-Code-Server

Write-Host '=== HARD assert Designer Mac ===' -ForegroundColor Cyan
Select-String -Path scripts/client/tests/test-hard-multi-agent-regressions.ps1 -Pattern 'Designer Mac|desSh|flock|connect.lock' | ForEach-Object {
  Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
Write-Host '--- designer connect.sh lock ---'
$desSh = Get-Content 'scripts/client/users/designer/connect.sh' -Raw
Write-Host ("has flock: {0}" -f ($desSh -match 'flock'))
Write-Host ("has connect.lock: {0}" -f ($desSh -match 'connect\.lock'))
Write-Host ("has enter_connect: {0}" -f ($desSh -match 'enter_connect_single_instance'))
Write-Host ("has MULTI: {0}" -f ($desSh -match 'MULTI_INSTANCE'))
Select-String -Path scripts/client/users/designer/connect.sh -Pattern 'lock|flock|single|enter_connect|MULTI' | Select-Object -First 20 | ForEach-Object {
  Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}

Write-Host "`n=== smart/curly quotes in connect.ps1 ===" -ForegroundColor Cyan
# find the assert
Select-String -Path scripts/client/tests/test-connect-pipeline.ps1 -Pattern 'smart/curly|curly|[\u2018\u2019\u201C\u201D]' | ForEach-Object {
  Write-Host ("ASSERT:{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
$win = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/windows/connect.ps1'))
$chars = @([char]0x2018, [char]0x2019, [char]0x201C, [char]0x201D, [char]0x2013, [char]0x2014)
$found = @()
for ($i=0; $i -lt $win.Length; $i++) {
  if ($chars -contains $win[$i]) {
    $start = [Math]::Max(0, $i-40); $len = [Math]::Min(80, $win.Length-$start)
    $found += "pos=$i ch=U+{0:X4} ctx=[{1}]" -f [int][char]$win[$i], ($win.Substring($start,$len) -replace "`r|`n"," ")
    if ($found.Count -ge 15) { break }
  }
}
if ($found.Count -eq 0) { Write-Host 'No curly quotes found by scan' } else { $found | ForEach-Object { Write-Host $_ } }

Write-Host "`n=== SshX timeout wrap assert ===" -ForegroundColor Cyan
Select-String -Path scripts/client/tests/test-connect-pipeline.ps1 -Pattern 'wraps SshX|timeout 45|bash -lc' | ForEach-Object {
  Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
# show Get-FunctionSource area for SshX
Select-String -Path scripts/client/windows/connect.ps1 -Pattern 'timeout 45|bash -lc|function SshX|Invoke-SshXCore|base64' | ForEach-Object {
  Write-Host ("WIN:{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
