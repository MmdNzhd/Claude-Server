$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
$lines = Get-Content -LiteralPath $log
$sids = @('42e5a213b16f','dd977f87c0d3','63c46c4b749e','32405f1370fe')
foreach ($sid in $sids) {
  Write-Output "======== SESSION $sid ========"
  $pat = '\[' + $sid + '\]'
  $sess = $lines | Where-Object { $_ -match $pat }
  Write-Output ("line_count=" + $sess.Count)
  Write-Output '--- filtered ---'
  $filter = 'STEP |TIMING|duration|elapsed|sec=|FAIL|ERROR|WARN|UPDATE|Reconnect|elevat|SINGLE_INSTANCE|mutex|unauthorized|Access denied|EXIT|session start|session end|CONNECT_OK|CONNECT_FAIL|Server setup|Cursor auth|Verifying|Mounting|GIT_MODE|PROC_|LAUNCH_|auth_relaunch|AdminFix|soft-stop|soft_stop|STEP_BEGIN|STEP_END|ms='
  $sess | Where-Object { $_ -match $filter } | ForEach-Object { $_ }
  Write-Output ''
}
