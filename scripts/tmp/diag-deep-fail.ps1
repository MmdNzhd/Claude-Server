$t=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1'
$i=0
foreach($line in $t){
  $i++
  if($line -match 'watchdog loads ACTIVE_MOUNT|durable local config'){
    Write-Output ("{0}:{1}" -f $i,$line.Trim())
    for($j=[Math]::Max(1,$i-5);$j -le [Math]::Min($t.Count,$i+8);$j++){
      Write-Output ("  {0}|{1}" -f $j,$t[$j-1])
    }
    Write-Output '---'
  }
}
Write-Output '=== watchdog ACTIVE_MOUNT ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\claude-self-heal.sh','D:\Smart\Claude-Code-Server\scripts\server\claude-automount.sh' -Pattern 'ACTIVE_MOUNT' | Select-Object -First 20 | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '=== connect-ui.sh local log ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.sh' -Pattern 'connect\.log|CFG_DIR|durable|local' | Select-Object -First 30 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
