Set-Location D:\Smart\Claude-Code-Server
Select-String -Path scripts/client/windows/connect.ps1 -Pattern 'function (Test-IsAdmin|Start-Elevated|SelfElevat|Request-Admin)|RunAs|WindowStyle|Restart-AsAdmin|elevat' |
  ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }
# show self-elev block
$lines=Get-Content scripts/client/windows/connect.ps1
for($i=0;$i -lt [Math]::Min(250,$lines.Count);$i++){
  if($lines[$i] -match 'Test-IsAdmin|RunAs|elevat|Start-Process'){
    # print nearby only once for elev block
  }
}
# find early elevation
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'if \(-not \(Test-IsAdmin\)\)|Start-Process.*-Verb RunAs|Restart.*Admin'){
    $a=[Math]::Max(0,$i-2); $b=[Math]::Min($lines.Count-1,$i+30)
    Write-Host "---- elev L$($i+1) ----"
    for($j=$a;$j -le $b;$j++){ Write-Host ("{0}|{1}" -f ($j+1),$lines[$j]) }
    break
  }
}
# live pack bat same?
$pack=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260720\windows\connect.bat'
Write-Host "`nPACK bat restart lines:"
Get-Content $pack | Select-Object -Skip 28 -First 20 | ForEach-Object -Begin{$i=29}-Process{ Write-Host ("{0}|{1}" -f $i,$_); $i++ }
