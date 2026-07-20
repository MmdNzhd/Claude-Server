$ErrorActionPreference='Continue'
$dir = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
Write-Output "DIR=$dir"
Write-Output "EXISTS=$(Test-Path $dir)"
Get-ChildItem $dir -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Output ("LOG={0} SIZE={1} MTIME={2}" -f $_.FullName, $_.Length, $_.LastWriteTime)
}
# Also common names
@(
  'connect.log',
  'connect-diagnostic.log',
  '*.log'
) | Out-Null
$logs = Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.log','.txt' -or $_.Name -match 'log' }
$logs | ForEach-Object { Write-Output ("FILE={0} SIZE={1}" -f $_.Name, $_.Length) }

$log = Join-Path $dir 'connect.log'
if (-not (Test-Path $log)) {
  Write-Output 'NO_connect.log'
  Get-ChildItem $dir | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String | Write-Output
  exit 0
}
Write-Output '======== connect.log (last 200 lines) ========'
Get-Content $log -Tail 200
Write-Output ''
Write-Output '======== connect.log (errors/warns) ========'
Select-String -Path $log -Pattern 'ERR|ERROR|FAIL|WARN|CURSOR_NOT|auth|AUTH|kill|TEMP|version|VERDICT|BROKEN' |
  Select-Object -Last 60 |
  ForEach-Object { $_.Line }
