$f = 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
# Get-CursorProfileProcesses + Stop-CursorServerProfileTree
Select-String -Path $f -Pattern 'function Get-CursorProfileProcesses|function Get-CursorMainProfileProcesses|function Stop-CursorServerProfileTree|function Stop-CursorServerProfileTreeIfNeeded|needKill|LAUNCH_KILL|pre_launch' |
  ForEach-Object { "{0}" -f $_.LineNumber }
Write-Host '---- Get-CursorProfileProcesses ----'
(Get-Content $f)[180..250] | ForEach-Object -Begin{$i=181}-Process{"{0,4}|{1}" -f $i,$_; $i++}
Write-Host '---- Stop-CursorServerProfileTree ----'
# find line
$lines = Get-Content $f
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Stop-CursorServerProfileTree\b') {
    $start=$i; break
  }
}
if ($null -ne $start) {
  for ($j=$start; $j -lt [Math]::Min($start+80,$lines.Count); $j++) {
    "{0,4}|{1}" -f ($j+1), $lines[$j]
  }
}
