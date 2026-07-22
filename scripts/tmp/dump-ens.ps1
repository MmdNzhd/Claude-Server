$lines = Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
for ($i=1310; $i -lt 1530; $i++) { '{0,4}|{1}' -f ($i+1), $lines[$i] }
Write-Host '--- function Ensure count ---'
($lines | Select-String 'function Ensure-SessionTunnel').LineNumber
