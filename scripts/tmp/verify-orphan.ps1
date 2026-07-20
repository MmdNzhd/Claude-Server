$g=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh'
Write-Output '=== remove_local_orphan_tunnel ==='
1162..1230 | ForEach-Object { if($_ -le $g.Count){ "{0,4}|{1}" -f $_, $g[$_-1] } }
Write-Output '=== Write-ConnectSessionContext in connect-ui ==='
$ui='D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1'
if(Test-Path $ui){
  Select-String -Path $ui -Pattern 'Write-ConnectSessionContext|ActiveProjectId|editorOpened|alreadyDown' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
} else { Write-Output 'missing connect-ui.ps1' }
Write-Output '=== CLEAR_MOUNT Reason param ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1' -Pattern 'function Clear-ServerActiveMount|Reason' | Select-Object -First 15 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
1105..1145 | ForEach-Object {
  $lines=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
  "{0,4}|{1}" -f $_, $lines[$_-1]
}
