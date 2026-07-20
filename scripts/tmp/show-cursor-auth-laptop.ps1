$f='D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1'
Write-Output "FILE=$f"
$lines=Get-Content $f
Write-Output ("TOTAL="+$lines.Count)
Write-Output '===== LINES 340-420 ====='
for($i=340;$i -le [Math]::Min(420,$lines.Count);$i++){ Write-Output ("{0,4}|{1}" -f $i,$lines[$i-1]) }
Write-Output '===== tmp / Remove-Item / TEMP hits ====='
Select-String -Path $f -Pattern '\$tmp|Remove-Item|TEMP|GetTemp|8\.3|ShortPath|Unexpected error' |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '===== Desktop package versions of this file ====='
$pkgs=@(
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\cursor-auth-laptop.ps1'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\cursor-auth-laptop.ps1'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\cursor-auth-laptop.ps1')
)
foreach($p in $pkgs){
  if(Test-Path $p){
    $h=(Get-FileHash $p -Algorithm SHA256).Hash.Substring(0,16)
    $n=(Get-Content $p).Count
    Write-Output ("EXISTS $p sha16=$h lines=$n")
    Select-String -Path $p -Pattern 'Remove-Item \$tmp' | ForEach-Object { "  L$($_.LineNumber):$($_.Line.Trim())" }
  } else { Write-Output "MISS $p" }
}
