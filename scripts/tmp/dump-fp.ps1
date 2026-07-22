$p='D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$lines=Get-Content $p
for($i=531;$i -le 546;$i++){ '{0,4}|{1}' -f ($i+1), $lines[$i] }
# also find line number
Select-String -Path $p -Pattern 'function Get-TunnelHostKeyFingerprint' | ForEach-Object { "FOUND $($_.LineNumber)" }
