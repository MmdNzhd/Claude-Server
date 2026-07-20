$root='D:\Smart\Claude-Code-Server\scripts\tmp'
Write-Output '=== REPORTS ==='
Get-ChildItem $root -Include FIX-AGENT-*.md,REVIEW-*.md,TEST-AGENT-*.md,TEST-SCOREBOARD.md -Recurse -EA SilentlyContinue |
  Sort-Object Name | ForEach-Object { "{0} {1}b {2}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString('HH:mm:ss') }

Write-Output '=== PIPELINE FAIL DETAIL ==='
Select-String -Path "$root\test-pipeline-out.txt" -Pattern 'FAIL ' -EA SilentlyContinue | ForEach-Object { $_.Line }

Write-Output '=== CURLY QUOTES in connect.ps1? ==='
$p='D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$bytes=[IO.File]::ReadAllBytes($p)
# UTF8 smart quotes: E2 80 98/99/9C/9D
$hits=0
for($i=0;$i -lt $bytes.Length-2;$i++){
  if($bytes[$i]-eq 0xE2 -and $bytes[$i+1]-eq 0x80 -and $bytes[$i+2] -in 0x98,0x99,0x9C,0x9D){ $hits++; if($hits -le 5){ "offset=$i" } }
}
"smart_quote_sequences=$hits"

Write-Output '=== HOT BAD PATTERNS ==='
$checks=@(
  @{n='sepidz@Admin'; p='publish'; pat='sepidz@Admin'},
  @{n='PushConf || true'; p='scripts/client/mac'; pat='\|\| true'},
  @{n='seq 1 4 tunnel'; p='scripts/client'; pat='seq 1 4'},
  @{n='ReadAllBytes log'; p='scripts/client'; pat='ReadAllBytes'},
  @{n='; true log'; p='scripts/client'; pat='; true'}
)
Set-Location 'D:\Smart\Claude-Code-Server'
foreach($c in $checks){
  $r=Select-String -Path (Get-ChildItem $c.p -Recurse -Include *.ps1,*.sh -EA SilentlyContinue) -Pattern $c.pat -EA SilentlyContinue | Select-Object -First 3
  if($r){ "HIT $($c.n): $($r.Count)+ e.g. $($r[0].Path):$($r[0].LineNumber)" } else { "CLEAN $($c.n)" }
}
