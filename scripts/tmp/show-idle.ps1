$c=Get-Content 'scripts/client/windows/connect.ps1'
for($i=1525;$i -lt 1580;$i++){ '{0,5}|{1}' -f ($i+1), $c[$i] }
Write-Host '==== recovery ===='
for($i=1600;$i -lt 1685;$i++){ '{0,5}|{1}' -f ($i+1), $c[$i] }
Write-Host '==== ensure spawn guard ===='
$g=Get-Content 'scripts/client/git-mode.ps1'
Select-String -Path 'scripts/client/git-mode.ps1' -Pattern 'LastEnsure|SpawnAt|5 second|TotalSeconds -lt 5|recent spawn' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line }
Write-Host '==== Sync no_proc region ===='
$n=(Select-String -Path 'scripts/client/git-mode.ps1' -Pattern 'no_proc_tcp_open').LineNumber | Select-Object -First 1
for($i=$n-15;$i -lt $n+25;$i++){ '{0,5}|{1}' -f ($i+1), $g[$i] }
Write-Host '==== session start editorOpened ===='
Select-String -Path 'scripts/client/windows/connect.ps1' -Pattern 'editorOpened = \$false|RecoveryGeneration = 0' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
