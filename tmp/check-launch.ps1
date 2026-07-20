Select-String -Path scripts\client\editor-launch.sh -Pattern 'user-data-dir|ClaudeServer|open_cursor|launch_cursor|folder-uri' |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)) }
'==== connect auth block ===='
$lines = Get-Content scripts\client\mac\connect.sh
for ($i=710; $i -le 780; $i++) { "{0}:{1}" -f $i, $lines[$i-1] }
