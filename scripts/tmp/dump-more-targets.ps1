Write-Output '=== Read-PostDisconnectKey ==='
$g=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
for($i=140;$i -le 180;$i++){ Write-Output ("{0,4}|{1}" -f $i, $g[$i-1]) }
Write-Output '=== CONTEXT AlreadyDown ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1' -Pattern 'AlreadyDown|ActiveMountId|EditorOpened|log_session_context|Write-ConnectSession' | Select-Object -First 25 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== Choose-Project WARN ==='
$c=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Pattern 'Enter a number or' -Context 3,3 | ForEach-Object { $_.ToString() }
Write-Output '=== Mac orphan+softfail region ==='
$sh=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh'
for($i=730;$i -le 810;$i++){ Write-Output ("{0,4}|{1}" -f $i, $sh[$i-1]) }
Write-Output '--- orphan ---'
for($i=1035;$i -le 1120;$i++){ Write-Output ("{0,4}|{1}" -f $i, $sh[$i-1]) }
Write-Output '=== tunnel_drop_session_action ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh' -Pattern 'tunnel_drop_session_action' | ForEach-Object LineNumber
$n=(Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh' -Pattern '^tunnel_drop_session_action').LineNumber
if($n){ for($i=$n;$i -le $n+40;$i++){ Write-Output ("{0,4}|{1}" -f $i, $sh[$i-1]) } }
Write-Output '=== Win PushConf dedupe (confirm prior fix) ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1' -Pattern 'LastPushConfKey|skip_duplicate|PUSH_CONF fail' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== versions ==='
Get-Content D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt
