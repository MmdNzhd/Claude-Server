$p = 'D:\Smart\Claude-Code-Server\scripts\tmp\connect-log-analysis.txt'
$l = Get-Content $p
Write-Output ("analysis_lines=" + $l.Count)
Write-Output '===== FIRST 150 ====='
$l | Select-Object -First 150
Write-Output '===== LAST 200 ====='
$l | Select-Object -Last 200
