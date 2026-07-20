$ErrorActionPreference='Stop'
$el='D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
Write-Output '=== CURSOR_NOT_FOUND hits ==='
Select-String -Path $el,'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Pattern 'CURSOR_NOT_FOUND' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '=== Resolve-EditorChoice (134-205) ==='
$lines=Get-Content $el
134..205 | ForEach-Object { "{0,4}|{1}" -f $_, $lines[$_-1] }
Write-Output '=== Find editor exe helpers ==='
Select-String -Path $el -Pattern 'function Resolve-Editor|Get-EditorExe|EditorCmd|Programs\\cursor|where.exe' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
