$ErrorActionPreference='Stop'
$p=(Resolve-Path 'scripts/client/windows/connect.ps1').Path
$c=[IO.File]::ReadAllText($p)
# Fix the mojibake em-dash in the expensive CIM comment
$c2=[regex]::Replace($c, 'expensive .{1,8} at most every 2s', 'expensive - at most every 2s')
if($c2 -eq $c){
  # try exact known garbage
  $c2=$c.Replace("expensive â€`"? at most", "expensive - at most")
}
# brute: replace any line containing CIM queries are expensive
$lines=$c -split "`r?`n", -1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'CIM queries are expensive'){
    $lines[$i]='                # Editor CIM queries are expensive - at most every 2s (was every 200ms).'
    Write-Host "fixed line $($i+1)"
  }
}
$out=($lines -join "`r`n")
[IO.File]::WriteAllText($p,$out)
# verify no curly quotes
$src=[IO.File]::ReadAllText($p)
$bad=$false
foreach($ch in @([char]0x201C,[char]0x201D,[char]0x2018,[char]0x2019)){
  if($src.IndexOf($ch) -ge 0){ $bad=$true; Write-Host "still has U+$([int]$ch)" }
}
if($bad){ throw 'curly quotes remain' }
Write-Host 'OK ascii clean'
