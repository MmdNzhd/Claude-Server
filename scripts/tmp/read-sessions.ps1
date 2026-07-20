$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
foreach ($sid in @('cfc05f473c9d','1661fd8c04ce')) {
  Write-Host ""
  Write-Host "======== SESSION $sid ========"
  $lines = Select-String -Path $log -Pattern "\[$sid\]" | ForEach-Object { $_.Line }
  Write-Host ("total_lines=" + $lines.Count)
  $lines | Where-Object {
    $_ -match 'FAIL |\[ERROR\]|\[WARN\]|push failed|script push|Admin|NEED_ADMIN|UAC|MOUNT|session start|session end|STEP end|STEP begin|Reconnect|OUTDATED|sha256|claude-mount|_emit|Path not|MENU|BOOTSTRAP|MULTI_INSTANCE|up_to_date|ENSURE|CONNECT_|SSH_QUOTE'
  } | ForEach-Object { $_ }
  Write-Host "--- TIMING (SSH_END ms>=800 or STEP ms) ---"
  $lines | Where-Object { $_ -match 'SSH_END exit=.*ms=(\d+)' } | ForEach-Object {
    if ($_ -match 'ms=(\d+)') { [pscustomobject]@{ms=[int]$Matches[1]; line=$_} }
  } | Sort-Object ms -Descending | Select-Object -First 15 | ForEach-Object { $_.line }
  $t0 = $null; $t1 = $null
  if ($lines[0] -match '^\[([^\]]+)\]') { $t0 = [datetime]::ParseExact($Matches[1],'yyyy-MM-dd HH:mm:ss.fff',$null) }
  $ready = $lines | Where-Object { $_ -match 'Ready|project_menu_shown|Loading projects ok' } | Select-Object -First 1
  $mountFail = $lines | Where-Object { $_ -match 'FAIL STEP name=Mounting' } | Select-Object -First 1
  Write-Host "first=$($lines[0])"
  Write-Host "menu_or_ready=$ready"
  Write-Host "mount_fail=$mountFail"
}
# Count FAIL vs ERROR orphans (ERROR without FAIL)
Write-Host "`n======== LOG CONTRACT SPOT ========"
$all = Get-Content $log | Where-Object { $_ -match '\[(cfc05f473c9d|1661fd8c04ce)\]' }
$err = @($all | Where-Object { $_ -match '\[ERROR\]' })
$fail = @($all | Where-Object { $_ -match 'FAIL ' })
Write-Host ("ERROR_lines=" + $err.Count + " FAIL_lines=" + $fail.Count)
$err | Where-Object { $_ -notmatch 'FAIL ' } | ForEach-Object { "ORPHAN_ERROR: $_" }
