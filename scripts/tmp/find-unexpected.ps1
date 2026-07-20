Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1','D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1','D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1' -Pattern 'Unexpected error|Laptop folder restored' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }

# show catch context in connect around Unexpected
$c=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$hits=Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Pattern 'Unexpected error'
foreach($h in $hits){
  $s=[Math]::Max(1,$h.LineNumber-15); $e=[Math]::Min($c.Count,$h.LineNumber+10)
  Write-Output "---- connect.ps1 $($h.LineNumber) ----"
  for($i=$s;$i -le $e;$i++){ Write-Output ("{0,4}|{1}" -f $i,$c[$i-1]) }
}

# also Sync-CursorAuthLaptop entrypoints / when disconnect calls it
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1','D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1' -Pattern 'cursor-auth-laptop|Sync-Cursor|Get-RemoteCursorAuthFromGolden|Invoke-CursorAuth' |
  Select-Object -First 40 |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
