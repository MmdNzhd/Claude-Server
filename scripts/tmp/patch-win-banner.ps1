Set-Location 'D:\Smart\Claude-Code-Server'
$p='scripts\client\git-mode.ps1'
$lines=Get-Content $p
# show exact lines 500-545 and 880-910
Write-Output '=== SYNC ==='
490..560 | ForEach-Object { if($_ -le $lines.Count){ '{0}|{1}' -f $_, $lines[$_-1] } }
Write-Output '=== ENSURE ==='
860..930 | ForEach-Object { if($_ -le $lines.Count){ '{0}|{1}' -f $_, $lines[$_-1] } }
