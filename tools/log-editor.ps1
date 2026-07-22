$log = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
$lines = Get-Content $log
# find session 5ec0076542e6 editor-related only, compact
$lines | Where-Object { $_ -match '5ec0076542e6' -and $_ -match 'EDITOR|Opening|LAUNCH|Start-Process|folder_reason|on_folder|Open-Editor|Invoke-Editor|WAIT|timeout|soft-stop|new.window|state_vscdb|AUTH ' } | ForEach-Object {
  # trim huge process dumps
  if ($_ -match 'PROCESSES snapshot') { 'PROCESS_SNAPSHOT (truncated)' ; return }
  if ($_.Length -gt 350) { $_.Substring(0,350) + '...[trunc]' } else { $_ }
}
Write-Host '---'
Write-Host ("state_vscdb_bytes hint from log:")
$lines | Where-Object { $_ -match 'state_vscdb=' } | Select-Object -Last 3
Write-Host '--- profile size ---'
$p = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\globalStorage\state.vscdb'
if (Test-Path $p) {
  $i = Get-Item $p
  Write-Host ("state.vscdb MB={0:N1} mtime={1}" -f ($i.Length/1MB), $i.LastWriteTime)
}
Get-Process Cursor -EA SilentlyContinue | Measure-Object | ForEach-Object { Write-Host ("Cursor_process_count={0}" -f $_.Count) }
