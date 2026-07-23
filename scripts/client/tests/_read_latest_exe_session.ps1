$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260722.log'
Write-Output ("LOG mtime=" + (Get-Item -LiteralPath $log).LastWriteTime.ToString('o') + " len=" + (Get-Item -LiteralPath $log).Length)
Write-Output '==== LAST 15 session start ===='
Select-String -LiteralPath $log -Pattern 'session start v' | Select-Object -Last 15 | ForEach-Object { $_.Line }
Write-Output '==== LAST 40 ERROR ===='
Select-String -LiteralPath $log -Pattern '\[ERROR\]' | Select-Object -Last 40 | ForEach-Object { $_.Line }
Write-Output '==== LAST 40 WARN (non-TRACE noise filter) ===='
Select-String -LiteralPath $log -Pattern '\[WARN\]' | Select-Object -Last 50 | ForEach-Object { $_.Line }
Write-Output '==== LAST 30 FAIL|UPDATE|EXIT|boot_error|UNHANDLED|popup|MessageBox|exception ===='
Select-String -LiteralPath $log -Pattern 'FAIL |EXIT_WAIT|boot_error|UNHANDLED|MessageBox|exception|require_fail|UPDATE:|local_exe|exe_only|Claude-Connect\.exe' |
  Select-Object -Last 40 | ForEach-Object { $_.Line }
Write-Output '==== TAIL 60 ===='
Get-Content -LiteralPath $log -Tail 60
