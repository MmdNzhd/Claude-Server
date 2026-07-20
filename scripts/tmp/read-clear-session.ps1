$f='D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$lines=Get-Content $f
for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match 'function Clear-SessionMount'){ $s=$i; break } }
for($j=$s;$j -lt [Math]::Min($s+60,$lines.Count);$j++){ "{0,4}|{1}" -f ($j+1),$lines[$j] }
