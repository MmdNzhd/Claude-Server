$p = 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1'
Write-Host '=== deploy-client-bundles matches ==='
Select-String -Path $p -Pattern 'SudoPassword|base64|non-interactive|installing with stored' | ForEach-Object {
  '{0}:{1}' -f $_.LineNumber, $_.Line.Trim()
}
Write-Host '=== lines 215-245 ==='
$lines = Get-Content $p
for ($i = 214; $i -le 244 -and $i -lt $lines.Count; $i++) {
  '{0}|{1}' -f ($i + 1), $lines[$i]
}
Write-Host '=== claude-mount ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh' -Pattern '_apply_git_scm|_warm_sshfs_cache' | ForEach-Object {
  '{0}:{1}' -f $_.LineNumber, $_.Line.Trim()
}
Write-Host '=== connect-update ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1' -Pattern 'up to date|unreachable|Update check' | ForEach-Object {
  '{0}:{1}' -f $_.LineNumber, $_.Line.Trim()
}
Write-Host '=== deploy-laptop-exec sed ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-laptop-exec.sh' -Pattern 'sed -i' | ForEach-Object {
  '{0}:{1}' -f $_.LineNumber, $_.Line.Trim()
}
Write-Host '=== sudoers ==='
Get-Content 'D:\Smart\Claude-Code-Server\scripts\server\sudoers.d\claude-client-deploy'
Write-Host '=== versions ==='
'REPO=' + (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
