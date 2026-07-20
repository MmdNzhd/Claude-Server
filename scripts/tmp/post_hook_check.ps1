$ErrorActionPreference = 'Continue'
Write-Host '=== desktop folder version ==='
$p1 = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\connect-version.txt'
if (Test-Path $p1) { Get-Content $p1 } else { Write-Host 'missing 20260717 folder version' }
Write-Host '=== publish folders ==='
Get-ChildItem 'C:\Users\Smart\Desktop\claude-publish' -Directory -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 6 |
  ForEach-Object { '{0}  {1}' -f $_.LastWriteTime.ToString('s'), $_.Name }

Write-Host '=== server version ==='
ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=no smart@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt'

Write-Host '=== server log markers (last hits) ==='
ssh -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no smart@192.168.250.70 'wc -c ~/.claude/logs/connect-20260719.log; echo ---SESS---; grep "session start v" ~/.claude/logs/connect-20260719.log | tail -10; echo ---BOOT---; grep BOOTSTRAP ~/.claude/logs/connect-20260719.log | tail -5; echo ---FAIL---; grep LOG_SYNC_FAIL ~/.claude/logs/connect-20260719.log | tail -5; echo ---TAIL---; tail -n 20 ~/.claude/logs/connect-20260719.log'

Write-Host '=== local log sessions ==='
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$dst = Join-Path $env:TEMP 'chk-local.log'
$fs = [IO.File]::Open($local, 'Open', 'Read', 'ReadWrite')
try { $o = [IO.File]::Create($dst); try { $fs.CopyTo($o) } finally { $o.Close() } } finally { $fs.Close() }
Write-Host ("local bytes={0}" -f (Get-Item $dst).Length)
Select-String -Path $dst -Pattern 'session start v' | Select-Object -Last 8 | ForEach-Object {
  $_.Line.Substring(0, [Math]::Min(150, $_.Line.Length))
}
Write-Host '=== local LOG_SYNC_FAIL / literal False lines ==='
Select-String -Path $dst -Pattern 'LOG_SYNC_FAIL' | Select-Object -Last 5 | ForEach-Object { $_.Line }
$falseHits = @(Select-String -Path $dst -SimpleMatch '] False' -ErrorAction SilentlyContinue)
Write-Host ("false_like_count={0}" -f $falseHits.Count)
if (Test-Path ($local + '.sync-offset')) {
  Write-Host ("watermark={0} size={1}" -f (Get-Content ($local + '.sync-offset') -Raw).Trim(), (Get-Item $local).Length)
} else { Write-Host 'watermark=MISSING' }
Remove-Item $dst -Force
Write-Host DONE
