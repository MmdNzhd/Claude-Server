Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' -Pattern 'CURSOR_NOT_FOUND|Find-Cursor|Get-Cursor|cursor\.exe|LocalAppData\\Programs\\cursor' |
  Select-Object -First 40 |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '--- function ---'
$lines=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$i=0; foreach($l in $lines){ $i++; if($l -match 'function.*(Cursor|Resolve-Editor)'){ "{0}:{1}" -f $i,$l.Trim() } }
