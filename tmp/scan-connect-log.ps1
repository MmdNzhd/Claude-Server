$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
Write-Output ("log_size={0}" -f (Get-Item $log).Length)
$patterns = @(
  '6ea2a5c8b600',
  'FAIL UNHANDLED',
  'Cannot overwrite',
  'LAUNCH_KILL',
  'PROC_START',
  'EDITOR_SEEN_CLEAR',
  'HEARTBEAT',
  'TUNNEL_DROP',
  'CLEAR_MOUNT',
  'auth_relaunch',
  'personal_main',
  'profile_main',
  'UNHANDLED'
)
foreach ($pat in $patterns) {
  $c = @(Select-String -Path $log -Pattern $pat -SimpleMatch).Count
  Write-Output ("count {0}={1}" -f $pat, $c)
}
Write-Output '--- FAIL/UNHANDLED LINES ---'
Select-String -Path $log -Pattern 'FAIL UNHANDLED|Cannot overwrite|UNHANDLED:' | ForEach-Object { $_.Line }
Write-Output '--- SESSION 6ea2 hits (first 30) ---'
Select-String -Path $log -Pattern '6ea2a5c8b600' | Select-Object -First 30 | ForEach-Object { $_.Line }
