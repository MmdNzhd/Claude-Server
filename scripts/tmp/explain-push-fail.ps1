Set-Location D:\Smart\Claude-Code-Server
Write-Host '=== PushOk / SERVER_SCRIPT_PUSH ===' -ForegroundColor Cyan
Select-String -Path scripts/client/windows/connect.ps1,scripts/client/git-mode.ps1 -Pattern 'SERVER_SCRIPT_PUSH|PushOk|script push|fixed:|pendingFixes|Initialize-ServerSession' |
  ForEach-Object { Write-Host ("{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length))) }

Write-Host "`n=== Initialize-ServerSession PushOk logic ===" -ForegroundColor Cyan
$lines = Get-Content scripts/client/windows/connect.ps1
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Initialize-ServerSession|PushOk|script push') {
    if ($lines[$i] -match 'function Initialize-ServerSession') {
      for ($j=$i; $j -lt [Math]::Min($i+120,$lines.Count); $j++) {
        Write-Host ("{0}|{1}" -f ($j+1), $lines[$j])
        if ($j -gt $i -and $lines[$j] -match '^function ') { break }
      }
      break
    }
  }
}
