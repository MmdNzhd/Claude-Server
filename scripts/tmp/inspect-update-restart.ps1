Set-Location D:\Smart\Claude-Code-Server
Write-Host '=== connect.bat update/restart ===' -ForegroundColor Cyan
Select-String -Path scripts/client/windows/connect.bat -Pattern 'update|restart|exit|START|cmd' -CaseSensitive:$false |
  ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }

Write-Host "`n=== connect-update.ps1 restart paths ===" -ForegroundColor Cyan
Select-String -Path scripts/client/windows/connect-update.ps1 -Pattern 'Restarting|Updated to|exit |Start-Process|connect\.bat|Relaunch|pending|swap|Live' |
  ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }

Write-Host "`n=== tail of connect-update around exit codes ===" -ForegroundColor Cyan
$lines = Get-Content scripts/client/windows/connect-update.ps1
# find Restarting
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'Restarting with updated|Updated to|exit 2|Start-Process') {
    $a=[Math]::Max(0,$i-8); $b=[Math]::Min($lines.Count-1,$i+25)
    Write-Host "----- around L$($i+1) -----"
    for ($j=$a; $j -le $b; $j++) { Write-Host ("{0}|{1}" -f ($j+1), $lines[$j]) }
  }
}
