Set-Location D:\Smart\Claude-Code-Server
Write-Host "=== TunnelDropLog param ==="
$i = 37
Get-Content scripts/client/git-mode.ps1 | Select-Object -Skip 36 -First 60 | ForEach-Object {
  if ($_ -match 'Pid|TunnelPid|bg_pid') { Write-Host ("{0}|{1}" -f $i, $_) }
  $i++
}
Write-Host "=== connect.ps1 TunnelDrop ==="
Select-String -Path scripts/client/windows/connect.ps1 -Pattern 'TunnelDropLog|TunnelPid|-Pid' | ForEach-Object {
  Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
Write-Host "=== Launch exhaust ==="
$i = 1546
Get-Content scripts/client/editor-launch.ps1 | Select-Object -Skip 1545 -First 45 | ForEach-Object {
  Write-Host ("{0}|{1}" -f $i, $_)
  $i++
}
Write-Host "=== session-log line 30 ==="
Get-Content scripts/client/tests/test-session-log-contracts.ps1 | Select-Object -Skip 27 -First 6 | ForEach-Object -Begin {$n=28} -Process { Write-Host ("{0}|{1}" -f $n, $_); $n++ }
Write-Host "=== pipeline hide assert ==="
Select-String -Path scripts/client/tests/test-connect-pipeline.ps1 -Pattern 'lt 3|rename|fail-fast' | ForEach-Object {
  Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
Write-Host "=== Opening launch StepOk ==="
Select-String -Path scripts/client/windows/connect.ps1 -Pattern 'Launch-RemoteEditor|StepOk|StepFail|Opening' | Select-Object -First 25 | ForEach-Object {
  Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
