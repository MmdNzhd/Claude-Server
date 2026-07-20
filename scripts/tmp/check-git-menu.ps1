$t=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1' -Raw
if($t -match 'git menu option[\s\S]{0,400}'){ $Matches[0] }
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1' -Pattern 'git menu' -Context 2,5
Write-Output '--- menu switch in connect.ps1 ---'
880..920 | ForEach-Object {
  $l=(Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')[$_-1]
  "{0,4}|{1}" -f $_, $l
}
