$ErrorActionPreference = 'Continue'
$root = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
$gs = Join-Path $root 'User\globalStorage'
$db = Join-Path $gs 'state.vscdb'
Write-Host "=== PROFILE SIZE ==="
if (Test-Path $root) {
  $sum = (Get-ChildItem $root -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
  Write-Host ("profile_total_GB={0:N2}" -f ($sum/1GB))
}
foreach ($f in @($db, "$db-wal", "$db-shm")) {
  if (Test-Path $f) { $i=Get-Item $f; Write-Host ("{0} bytes={1} MB={2:N1}" -f $i.Name, $i.Length, ($i.Length/1MB)) }
}
Write-Host "=== TOP 25 FILES ==="
Get-ChildItem $root -Recurse -File -EA SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 25 |
  ForEach-Object { "{0,12:N0}  {1}" -f $_.Length, $_.FullName.Replace($root, '.') }

Write-Host "=== SQLITE3 ==="
$sqlite = Get-Command sqlite3 -EA SilentlyContinue
if ($sqlite) {
  Write-Host "sqlite3=$($sqlite.Source)"
  & sqlite3 $db "SELECT COUNT(*) AS cnt FROM ItemTable;"
  & sqlite3 $db "SELECT key, length(value) AS n FROM ItemTable ORDER BY n DESC LIMIT 15;"
  & sqlite3 $db "SELECT key, length(value) FROM ItemTable WHERE key LIKE '%chat%' OR key LIKE '%composer%' OR key LIKE '%aichat%' OR key LIKE '%history%' OR key LIKE '%checkpoint%' OR key LIKE '%cursorDisk%' OR key LIKE '%agent%' ORDER BY length(value) DESC LIMIT 30;"
} else {
  Write-Host 'sqlite3=MISSING - trying python'
  python -c @"
import sqlite3, os
p = r'''$db'''
con = sqlite3.connect(p)
cur = con.cursor()
cur.execute('SELECT COUNT(*) FROM ItemTable')
print('count', cur.fetchone()[0])
cur.execute('SELECT key, length(value) FROM ItemTable ORDER BY length(value) DESC LIMIT 15')
for k,n in cur.fetchall():
    print(n, k[:120] if k else k)
cur.execute(\"\"\"SELECT key, length(value) FROM ItemTable WHERE key LIKE '%chat%' OR key LIKE '%composer%' OR key LIKE '%aichat%' OR key LIKE '%history%' OR key LIKE '%checkpoint%' OR key LIKE '%cursorDisk%' OR key LIKE '%agent%' ORDER BY length(value) DESC LIMIT 25\"\"\")
print('--- keyword keys ---')
for k,n in cur.fetchall():
    print(n, (k or '')[:140])
con.close()
"@
}

Write-Host "=== CURSOR PROCS ==="
Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -EA SilentlyContinue | ForEach-Object {
  $cl = $_.CommandLine
  $kind = if ($cl -match 'ClaudeServerCursorProfile') { 'SERVER' } elseif ($cl -match 'user-data-dir') { 'OTHER_PROFILE' } else { 'DEFAULT' }
  "pid=$($_.ProcessId) kind=$kind wsMB=$([math]::Round((Get-Process -Id $_.ProcessId -EA SilentlyContinue).WorkingSet64/1MB,0))"
} | Select-Object -First 40

Write-Host "=== RECENT LOG ERRORS ==="
$logRoot = Join-Path $root 'logs'
if (Test-Path $logRoot) {
  Get-ChildItem $logRoot -Directory | Sort-Object Name -Descending | Select-Object -First 3 | ForEach-Object {
    Write-Host ("logdir=" + $_.Name)
    Get-ChildItem $_.FullName -Recurse -Filter '*.log' -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 8 | ForEach-Object {
      $hits = Select-String -Path $_.FullName -Pattern 'timeout|unresponsive|extension host|Agent Execution|Out of memory|heap|ENOSPC|Timed Out' -EA SilentlyContinue | Select-Object -Last 5
      if ($hits) { Write-Host ("FILE=" + $_.FullName); $hits | ForEach-Object { $_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)) } }
    }
  }
}
