Write-Output '=== Win ORPHAN skip ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1' -Pattern 'ORPHAN_TUNNEL|skip_current|LastTunnelSpawn' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
$g=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$n=(Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1' -Pattern 'function Remove-LocalOrphanTunnel|ORPHAN_TUNNEL: skip').LineNumber | Select-Object -First 1
# find Remove-LocalOrphan
for($i=300;$i -le 360;$i++){ Write-Output ("{0,4}|{1}" -f $i, $g[$i-1]) }
Write-Output '=== CONTEXT fn ==='
$u=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1'
$start=0
for($i=0;$i -lt $u.Count;$i++){ if($u[$i] -match 'function Write-ConnectSessionContext'){ $start=$i; break } }
for($j=$start;$j -lt $start+50;$j++){ Write-Output ("{0,4}|{1}" -f ($j+1), $u[$j]) }
Write-Output '=== Choose-Project choice read ==='
$c=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
for($i=860;$i -le 900;$i++){ Write-Output ("{0,4}|{1}" -f $i, $c[$i-1]) }
# SoftFailCount init on mac
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh' -Pattern '_TUNNEL_SYNC_FAIL|_TUNNEL_SOFT|LAST_TUNNEL_SPAWN' | Select-Object -First 20 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
