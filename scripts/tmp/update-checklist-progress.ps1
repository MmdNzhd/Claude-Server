$ErrorActionPreference='Stop'
$p='scripts/tmp/connect-fix-100.md'
$c=[IO.File]::ReadAllText((Resolve-Path $p))
# Mark completed ranges we verified
$doneIds = 1..20 + 21,22,33,34,41,42,43,44,46,48,49,50,51,52,53,58,61,62,73,74,76,77,78,79,80,83,89,90,93,94,95,96,99
foreach($id in $doneIds){
  $pat = "(?m)^($id)\. \[ \]"
  $c = [regex]::Replace($c, $pat, '$1. [x]')
}
[IO.File]::WriteAllText((Resolve-Path $p), $c)
$done = ([regex]::Matches($c, '(?m)^\d+\. \[x\]')).Count
$todo = ([regex]::Matches($c, '(?m)^\d+\. \[ \]')).Count
Write-Host "DONE=$done TODO=$todo"
