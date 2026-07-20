# Check corruption around sync_cursor_golden_auth_status end
$lines = Get-Content scripts\client\git-mode.sh
$start = ($lines | Select-String -Pattern '^sync_cursor_golden_auth_status' | Select-Object -First 1).LineNumber
"start=$start"
for ($i=$start-1; $i -lt [Math]::Min($start+120, $lines.Count); $i++) {
  "{0}:{1}" -f ($i+1), $lines[$i]
}
'==== get_cursor_remote_profile_dir ===='
$g = ($lines | Select-String -Pattern 'get_cursor_remote_profile_dir\(\)|ClaudeServerCursorProfile' | Select-Object -First 15)
$g | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
'==== connect.sh auth ===='
Select-String -Path scripts\client\mac\connect.sh -Pattern 'sync_cursor|Cursor auth|AUTH_|sqlite' |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
'==== mktemp connect-ui ===='
Select-String -Path scripts\client\connect-ui.sh -Pattern 'mktemp' | ForEach-Object { $_.Line.Trim() }
