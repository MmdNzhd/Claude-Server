$lines=Get-Content -LiteralPath 'C:\Users\Smart\Downloads\Telegram Desktop\connect (2).log'
Write-Output '===== DIAGNOSTIC BLOCK ====='
$lines | Select-String -Pattern 'DIAGNOSTIC|SESSION_STATUS|VERDICT_|NEXT_ACTION|LIKELY_CAUSE|FIX=|ENV |AUTH |EDITOR |MOUNT ok|cursor_version|profile=' |
  Select-Object -First 60 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '===== PATH ANOMALIES ====='
$lines | Select-String -Pattern 'claude-code\\claude-code|Telegram Desktop|GIT_MODE|git=off|laptop_path' |
  Select-Object -First 25 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
