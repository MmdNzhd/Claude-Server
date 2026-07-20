$f='D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$lines=Get-Content $f
# Test-RemoteEditorInAgentHome
for ($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match 'function Test-RemoteEditorInAgentHome'){ $s=$i; break } }
if($null -ne $s){ for($j=$s;$j -lt [Math]::Min($s+50,$lines.Count);$j++){ "{0,4}|{1}" -f ($j+1),$lines[$j] } }
Write-Host '==== Get-CursorMainProfileProcesses / Get-CursorProfileProcesses ===='
for ($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match 'function Get-CursorProfileProcesses\b|function Get-CursorMainProfileProcesses\b'){ 
  for($j=$i;$j -lt [Math]::Min($i+45,$lines.Count);$j++){ "{0,4}|{1}" -f ($j+1),$lines[$j] }
  Write-Host '----'
}}
