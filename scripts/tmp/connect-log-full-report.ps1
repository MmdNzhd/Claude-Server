#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
$i = Get-Item $path
$lines = Get-Content $path

function Hits([string]$pat) { @($lines | Select-String -Pattern $pat) }
function ShowHits($title, $pat, $max=200) {
  Write-Output ""
  Write-Output "===== $title ====="
  $h = Hits $pat
  Write-Output ("count=" + $h.Count)
  $h | Select-Object -First $max | ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
  if ($h.Count -gt $max) { Write-Output ("... truncated, total=" + $h.Count) }
}

Write-Output "FILE=$($i.FullName)"
Write-Output "SIZE=$($i.Length) bytes"
Write-Output "MTIME=$($i.LastWriteTime)"
Write-Output "LINES=$($lines.Count)"
Write-Output "FIRST_TS=$((($lines[0] -split ']')[0]).TrimStart('['))"
Write-Output "LAST_TS=$((($lines[-1] -split ']')[0]).TrimStart('['))"

Write-Output ""
Write-Output "===== LEVEL COUNTS ====="
foreach ($lvl in @('ERROR','WARN','INFO','DEBUG','TRACE')) {
  $c = @($lines | Select-String -Pattern "\[$lvl\]").Count
  Write-Output ("$lvl=$c")
}

Write-Output ""
Write-Output "===== ALL UNIQUE VERDICT / STATUS CODES ====="
$lines | Select-String -Pattern 'VERDICT_CODE=|SESSION_STATUS=|VERDICT_SUMMARY=' |
  ForEach-Object { $_.Line -replace '.*\[.*?\]\s*','' } |
  Sort-Object -Unique

Write-Output ""
Write-Output "===== ALL STEP begin/end ====="
$lines | Select-String -Pattern 'STEP begin:|STEP end:' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== SESSION / LOOP / RECOVERY ====="
$lines | Select-String -Pattern 'session start|session end|SESSION_LOOP|RECOVERY_|TUNNEL: |CLEAR_MOUNT|ENSURE_TUNNEL (ok|spawned|start|killing)|ACTIVE_MOUNT server|PROJECT: id=' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

ShowHits 'ALL ERROR LINES' '\[ERROR\]' 100
ShowHits 'ALL WARN LINES' '\[WARN\]' 100

Write-Output ""
Write-Output "===== AUTH ====="
$lines | Select-String -Pattern 'AUTH_|AUTH:|cursor-auth|AUTH_SYNC|AUTH_DECISION' |
  Where-Object { $_.Line -notmatch 'PERF\[' } |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== EDITOR / LAUNCH (all non-cim) ====="
$lines | Select-String -Pattern 'LAUNCH_|EDITOR_|Opening Cursor|PROC_START|use_new_window|profile_all|profile_main|already_on_folder|ClaudeServerCursorProfile|folder-uri|kill|Force|preserve' |
  Where-Object { $_.Line -notmatch 'PERF\[cim_query\]' } |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== MOUNT CHECKS ====="
$lines | Select-String -Pattern 'claude-mount |MOUNT ok|mount up|mount down|ACTIVE_MOUNT|path_entry_count|mountpoint=' |
  Where-Object { $_.Line -notmatch 'mount_list=ai\|' } |
  Select-Object -First 80 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== GIT MODE ====="
$lines | Select-String -Pattern 'GIT_MODE|git_mode|GITMODE: (HIDE|SERVER|PUSH_CONF|STALE)' |
  Select-Object -First 40 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== SSH FAILURES (exit!=0) ====="
$lines | Select-String -Pattern 'SSH_END exit=[1-9]' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== DIAGNOSTIC REPORT HEADERS + VERDICTS ====="
$lines | Select-String -Pattern 'DIAGNOSTIC REPORT|SESSION_STATUS=|VERDICT_CODE=|VERDICT_SUMMARY=|TUNNEL up=|EDITOR on_folder=|EDITOR state=' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== STATUS_OK SAMPLE (first/last/count) ====="
$ok = Hits 'STATUS_OK'
Write-Output ("STATUS_OK_count=" + $ok.Count)
if ($ok.Count -gt 0) {
  Write-Output ("first=" + $ok[0].LineNumber + "|" + $ok[0].Line.Trim())
  Write-Output ("last=" + $ok[-1].LineNumber + "|" + $ok[-1].Line.Trim())
}

Write-Output ""
Write-Output "===== VERSION / UPDATE ====="
$lines | Select-String -Pattern '2026071[0-9]\.\d+|connect_version|Client update|Updated to|ConnectVersion' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== PERF SUMMARIES ====="
$lines | Select-String -Pattern 'PERF\[session_open_summary\]|PERF\[launch_total\]|PERF\[launch_' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== ORPHAN / KILL ====="
$lines | Select-String -Pattern 'ORPHAN|killing|Stop-Cursor|Force|preserve_open|LAUNCH_KILL' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== FIXES FLAGS ====="
$lines | Select-String -Pattern 'fixes=F' |
  Select-Object -First 20 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ""
Write-Output "===== END OF STRUCTURED REPORT ====="
