$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Write-Host "exists=$(Test-Path $log) path=$log"
$patterns = @(
  'LAUNCH_KILL',
  'auth_relaunch_never_kill',
  'hard_refuse',
  'CONNECT_VERSION=',
  'OUTDATED',
  'Conversation data missing',
  'missing blob'
)
$rx = ($patterns -join '|')
Select-String -Path $log -Pattern $rx | Select-Object -Last 60 | ForEach-Object { $_.Line }
Write-Host '--- versions seen tonight ---'
Select-String -Path $log -Pattern 'CONNECT_VERSION=' | ForEach-Object {
  if ($_.Line -match 'CONNECT_VERSION=([^\s]+)') { $Matches[1] }
} | Group-Object | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) x$($_.Count)" }
Write-Host '--- LAUNCH_KILL lines (all) ---'
Select-String -Path $log -Pattern 'LAUNCH_KILL' | ForEach-Object { $_.Line }
