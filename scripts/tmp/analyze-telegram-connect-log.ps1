#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$path = 'C:\Users\Smart\Downloads\Telegram Desktop\connect (2).log'
if (-not (Test-Path -LiteralPath $path)) {
  Write-Output "MISS: $path"
  Get-ChildItem 'C:\Users\Smart\Downloads\Telegram Desktop' -Filter 'connect*.log' -EA SilentlyContinue |
    ForEach-Object { Write-Output ("FOUND " + $_.FullName + " len=" + $_.Length + " mtime=" + $_.LastWriteTime) }
  exit 1
}
$i = Get-Item -LiteralPath $path
$lines = Get-Content -LiteralPath $path
Write-Output "FILE=$($i.FullName)"
Write-Output "SIZE=$($i.Length) MTIME=$($i.LastWriteTime) LINES=$($lines.Count)"
if ($lines.Count -gt 0) {
  Write-Output "FIRST=$($lines[0])"
  Write-Output "LAST=$($lines[-1])"
}

Write-Output ''
Write-Output '===== LEVEL COUNTS ====='
foreach ($lvl in @('ERROR','WARN','INFO','DEBUG','TRACE')) {
  Write-Output ("$lvl=" + @($lines | Select-String -Pattern "\[$lvl\]").Count)
}

Write-Output ''
Write-Output '===== VERSION / SCRIPT DIR ====='
$lines | Select-String -Pattern 'session start|connect_version|script_dir|202607|Claude-code-sepidz|claude-code-client' |
  Select-Object -First 30 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '===== ALL ERROR ====='
$lines | Select-String -Pattern '\[ERROR\]|Unexpected error|UNHANDLED|MH972|Remove-Item|Timed Out|TUNNEL_DOWN|SESSION_STATUS=BROKEN' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '===== ALL WARN ====='
$lines | Select-String -Pattern '\[WARN\]' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '===== STEPS ====='
$lines | Select-String -Pattern 'STEP begin:|STEP end:|PROJECT: id=|ACTIVE_MOUNT server|SESSION_LOOP|RECOVERY_|LAUNCH_|AUTH_|TUNNEL: |CLEAR_MOUNT|Laptop folder|Disconnect|ORPHAN|cursor-auth|Unexpected|UNHANDLED' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '===== VERDICTS ====='
$lines | Select-String -Pattern 'VERDICT_|SESSION_STATUS=|STATUS_OK|CURSOR_ON_FOLDER' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '===== AUTH / TEMP / SHORT PATH ====='
$lines | Select-String -Pattern 'AUTH_|cursor-auth|TEMP|MH972|8\.3|golden|Sync-Cursor|Unexpected|Remove-Item|folder restored' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '===== USER / HOST / PORT / PROJECT ====='
$lines | Select-String -Pattern 'user=|hostname|port=|PROJECT:|alias=|server=|hossein|sepidz|frontend|front|GIT_MODE|git_mode|elevated' |
  Select-Object -First 50 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '===== HEAD 80 ====='
$lines | Select-Object -First 80 | ForEach-Object { $_ }

Write-Output ''
Write-Output '===== TAIL 100 ====='
$lines | Select-Object -Last 100 | ForEach-Object { $_ }
