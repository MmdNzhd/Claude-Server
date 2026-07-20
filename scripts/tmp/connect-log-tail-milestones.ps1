$path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
$lines = Get-Content $path
Write-Output '=== LAUNCH / RECOVERY / STATUS (filtered) ==='
$lines | Select-String -Pattern 'LAUNCH_|RECOVERY_|STATUS_OK|SESSION_STATUS|VERDICT_|Opening Cursor|MOUNT ok|ACTIVE_MOUNT server|ORPHAN|killing|preserve|Force|pre_launch|session start|TUNNEL: connection|WARN: Recovery|editor_opened|use_new_window|profile_all|profile_main|cold_start|POST_RECOVERY|skip_editor' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output ''
Write-Output '=== SECOND DIAGNOSTIC ==='
$lines | Select-String -Pattern 'DIAGNOSTIC REPORT|SESSION_STATUS|VERDICT_|EDITOR on_folder|MOUNT ok|TUNNEL up=' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
