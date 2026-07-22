$log = 'C:\Users\Smart\.config\claude-connect\logs\connect-20260720.log'
Write-Output "=== KILL/AUTH LINES ==="
$pat = 'LAUNCH_KILL|soft-stop|SOFT_STOP|AUTH_RELAUNCH|Stop-Process|taskkill|Clear-SessionMount|clear_session_mount|CloseMainWindow|AUTH_FORCE|relaunch|force_auth|Kill-Cursor|Stop-Cursor|EDITOR_STOP|soft stop|SoftStop'
Select-String -Path $log -Pattern $pat | ForEach-Object {
  "{0}:{1}" -f $_.LineNumber, $_.Line
}
Write-Output "=== SESSIONS AFTER 1650 KEY ==="
Select-String -Path $log -Pattern '\[2026-07-20 (16:5[0-9]|1[7-9]:|2[0-3]:)' | Where-Object {
  $_.Line -match 'LAUNCH_KILL|soft-stop|SOFT_STOP|AUTH|Kill|Clear-Session|SESSION_LOOP|editor_opened|CONNECT_START|CONNECT_END|force_auth|EDITOR_|relaunch|PROFILE|ClaudeServer|SESSION_OPEN|disconnect|Cleanup|CLEANUP'
} | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line }
