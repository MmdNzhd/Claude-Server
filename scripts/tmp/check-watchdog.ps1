$deep=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1' -Raw
if($deep -match 'function Get-ServerFile[\s\S]{0,500}'){ $Matches[0].Substring(0,[Math]::Min(400,$Matches[0].Length)) }
$wd='D:\Smart\Claude-Code-Server\scripts\server\claude-watchdog.sh'
if(Test-Path $wd){
  Write-Output 'watchdog exists'
  Select-String -Path $wd -Pattern '_load_active_mount|ACTIVE_MOUNT|local_id' | Select-Object -First 15 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
} else { Write-Output 'watchdog MISSING' }
