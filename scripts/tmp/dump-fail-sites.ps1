Set-Location 'D:\Smart\Claude-Code-Server'
# curly deep scan
$p='scripts\client\windows\connect.ps1'
$t=[IO.File]::ReadAllText($p)
$i=0
foreach($ch in $t.ToCharArray()){
  $c=[int]$ch
  if($c -ge 0x2010 -and $c -le 0x2027){ $i++; if($i -le 15){ "U+{0:X4} at index near..." -f $c } }
}
"unicode_punct_count=$i match_curly=$($t -match '[\u201C\u201D\u2018\u2019]')"

# how pipeline loads
Select-String -Path scripts\client\tests\test-connect-pipeline.ps1 -Pattern 'curly|connect\.ps1|Get-Content|UTF' -Context 2,2

# banner_miss block
$lines=Get-Content scripts\client\git-mode.ps1
500..540 | ForEach-Object { "{0}:{1}" -f $_, $lines[$_-1] }
Write-Output '--- ENSURE banner ---'
860..900 | ForEach-Object { if($_ -le $lines.Count){ "{0}:{1}" -f $_, $lines[$_-1] } }

# recover + seq
$gl=Get-Content scripts\client\git-mode.sh
880..920 | ForEach-Object { "{0}:{1}" -f $_, $gl[$_-1] }
Write-Output '--- recover ---'
990..1020 | ForEach-Object { "{0}:{1}" -f $_, $gl[$_-1] }

# credentials
Get-Content publish\Get-DeployCredentials.ps1 | Select-Object -First 80
