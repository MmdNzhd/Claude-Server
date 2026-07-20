$ErrorActionPreference='Stop'
$files=@(
  'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\connect-diagnostic.ps1'
)
foreach($f in $files){
  Select-String -Path $f -Pattern 'CURSOR_NOT_FOUND|Resolve-EditorExe|Get-EditorCommand|where\.exe cursor|LocalAppData\\Programs\\cursor|editor conf' |
    ForEach-Object { "$(Split-Path $f -Leaf):$($_.LineNumber):$($_.Line.Trim())" }
}
Write-Output '--- Resolve-EditorChoice body ---'
$lines=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
134..210 | ForEach-Object { "{0,4}|{1}" -f $_, $lines[$_-1] }
