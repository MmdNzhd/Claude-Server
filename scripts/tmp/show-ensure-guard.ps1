$g=Get-Content 'scripts/client/git-mode.ps1'
for($i=830;$i -lt 920;$i++){ '{0,5}|{1}' -f ($i+1), $g[$i] }
Write-Host '==== vars top ===='
for($i=30;$i -lt 50;$i++){ '{0,5}|{1}' -f ($i+1), $g[$i] }
