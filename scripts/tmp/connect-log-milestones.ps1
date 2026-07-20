#Requires -Version 5.1
$path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
$lines = Get-Content $path
Write-Output '=== FIRST 120 ==='
$lines | Select-Object -First 120 | ForEach-Object { $_ }
Write-Output ''
Write-Output '=== MILESTONE MATCHES ==='
$pats = 'session start|session end|ACTIVE_MOUNT|mount up|mount down|EDITOR|Open-Editor|Launch|CURSOR|profile|TUNNEL|STATUS_OK|STATUS_|VERDICT|project=|GIT_MODE|auto reconnect|Recovery|BROKEN|OK |FAIL|ssh -R|Port '
$lines | Select-String -Pattern $pats |
  Where-Object { $_.Line -notmatch 'PERF\[cim_query\]|TUNNEL_SYNC: bg_alive|TUNNEL_UP port=.*cache=1' } |
  Select-Object -First 120 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output ''
Write-Output '=== MORE MILESTONES (next) ==='
$hits = $lines | Select-String -Pattern $pats |
  Where-Object { $_.Line -notmatch 'PERF\[cim_query\]|TUNNEL_SYNC: bg_alive|TUNNEL_UP port=.*cache=1' }
$hits | Select-Object -Skip 120 -First 80 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output ''
Write-Output '=== PROFILE/EDITOR SPECIFIC ==='
$lines | Select-String -Pattern 'profile_procs|ClaudeServerCursorProfile|new-window|LAUNCH_|editorOpened|OpenCursor|Start-Process.*Cursor|preserving|kill' -CaseSensitive:$false |
  Select-Object -First 50 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
