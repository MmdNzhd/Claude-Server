$el='D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
# Find Ensure-EditorOnPath and Get-EditorNativeExe and CURSOR_NOT_FOUND
Select-String -Path $el,'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1','D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1' -Pattern 'CURSOR_NOT_FOUND|Ensure-EditorOnPath|Get-EditorNativeExe|function Ensure-Editor' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '==== Ensure-EditorOnPath ===='
$lines=Get-Content $el
# find line of function
$start = ($lines | Select-String -Pattern 'function Ensure-EditorOnPath').LineNumber
if(-not $start){ $start = ($lines | Select-String -Pattern 'function Get-EditorNativeExe').LineNumber }
Write-Output "start=$start"
if($start){ $start..($start+50) | ForEach-Object { if($_ -le $lines.Count){ "{0,4}|{1}" -f $_, $lines[$_-1] } } }
Write-Output '==== Get-EditorNativeExe ===='
$start2 = ($lines | Select-String -Pattern 'function Get-EditorNativeExe').LineNumber
Write-Output "start2=$start2"
if($start2){ $start2..($start2+40) | ForEach-Object { if($_ -le $lines.Count){ "{0,4}|{1}" -f $_, $lines[$_-1] } } }
