$log='D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'
Write-Output '=== FARZAD all tunnel-ish lines (unique patterns) ==='
$hits = Select-String -Path $log -Pattern 'TUNNEL|tunnel|forward|ORPHAN|ENSURE|RECOVERY|alreadyDown|banner|soft_fail|DROP|reconnect|fallthrough|BgTunnel|ssh.*-R'
$hits | ForEach-Object {
  if ($_.Line -match '\]\s*(?:\[.*?\]\s*)?([A-Z_]+)') { $Matches[1] } else { 'OTHER' }
} | Group-Object | Sort-Object Count -Descending | Select-Object -First 40 | ForEach-Object { "{0,5} {1}" -f $_.Count, $_.Name }

Write-Output '=== sample ENSURE/ORPHAN/tunnel lines ==='
$hits | Select-Object -First 5 | ForEach-Object { $_.Line.Trim().Substring(0,[Math]::Min(180,$_.Line.Trim().Length)) }
Write-Output '...'
$hits | Select-Object -Last 25 | ForEach-Object { $_.Line.Trim().Substring(0,[Math]::Min(200,$_.Line.Trim().Length)) }

Write-Output '=== timeline session gaps (silent death?) ==='
$starts = Select-String -Path $log -Pattern 'session start|session end|ENSURE_TUNNEL|ORPHAN|CLEAR_MOUNT|user_quit|keychar=|CURSOR_ON_FOLDER|BOOTSTRAP'
$starts | ForEach-Object { "{0} | {1}" -f $_.Line.Substring(1,23), ($_.Line -replace '^.*\]\s*','').Substring(0,[Math]::Min(120,($_.Line -replace '^.*\]\s*','').Length)) } | Select-Object -Last 60
