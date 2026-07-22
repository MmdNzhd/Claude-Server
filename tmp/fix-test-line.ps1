$p = 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-editor-launch-strategies.ps1'
$lines = Get-Content $p
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'AuthRelaunch|auth_relaunch|hard_refuse') {
    '{0}: {1}' -f ($i+1), $lines[$i]
  }
}
# fix line properly
$out = foreach ($line in $lines) {
  if ($line -match "AuthRelaunch never soft-stops|LAUNCH_KILL: reason=auth_relaunch|auth_relaunch_never_kill") {
    "Assert (`$launchSrc -match 'auth_relaunch_never_kill|hard_refuse_') 'AuthRelaunch never soft-stops profile'"
  } else { $line }
}
[IO.File]::WriteAllLines($p, $out)
& powershell -NoProfile -ExecutionPolicy Bypass -File $p
Write-Host "EXIT=$LASTEXITCODE"
