$root='D:\Smart\Claude-Code-Server'
Write-Output '======== CONNECT-UPDATE.PS1 FULL FLOW ========'
$u=Get-Content "$root\scripts\client\windows\connect-update.ps1"
Write-Output ("lines=" + $u.Count)
# key sections by line ranges
@(1..10; 200..240; 280..320; 340..390; 430..445) | Select-Object -Unique | ForEach-Object {
  if($_ -le $u.Count){ "{0,4}|{1}" -f $_, $u[$_-1] }
}
Write-Output '======== MAC UPDATE EXIT/EXEC ========'
Select-String -Path "$root\scripts\client\mac\connect-update.sh","$root\scripts\client\mac\connect.sh" -Pattern 'exit |exec |UPDATE|version|scp|atomic|tmp|flock|lock' | Select-Object -First 50 | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '======== SESSION LOOP WHAT HOLDS STATE ========'
Select-String -Path "$root\scripts\client\windows\connect.ps1" -Pattern 'sessionLoop|BgTunnel|script:|while |ReadKey|Ensure-Session|Sync-Session' | Select-Object -First 40 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '======== DEPLOY BUNDLE LAYOUT ========'
Select-String -Path "$root\scripts\server\commands\deploy-client-bundle.sh" -Pattern 'BUNDLE|manifest|connect-version|install|chmod' | Select-Object -First 35 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '======== DOCS AUTO-UPDATE ========'
Select-String -Path "$root\docs\client-connect.md","$root\CLAUDE.md" -Pattern 'auto-update|connect-update|bundle|relaunch|need_relaunch' | ForEach-Object { "$($_.Filename):$($_.Line.Trim())" }
