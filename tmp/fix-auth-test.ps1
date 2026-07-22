$p = 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-editor-launch-strategies.ps1'
$t = [IO.File]::ReadAllText($p)
# Update assertion: AuthRelaunch must NEVER soft-stop
$t2 = $t -replace "Assert \(\`$el -match 'AuthRelaunch[^']*soft-stop[^']*'\) 'AuthRelaunch soft-stops profile'", "Assert (`$el -match 'auth_relaunch_never_kill|hard_refuse_') 'AuthRelaunch never soft-stops profile'"
if ($t2 -eq $t) {
  # try looser
  if ($t -match "AuthRelaunch soft-stops") {
    $t2 = $t -replace "AuthRelaunch soft-stops profile", "AuthRelaunch never soft-stops profile"
    $t2 = $t2 -replace "(`\$el -match ')([^']+)('\) 'AuthRelaunch never soft-stops profile')", "`$1auth_relaunch_never_kill|hard_refuse_`$3"
  }
}
# More reliable line-based
$lines = Get-Content $p
$out = foreach ($line in $lines) {
  if ($line -match "AuthRelaunch soft-stops") {
    "  Assert (`$el -match 'auth_relaunch_never_kill|hard_refuse_') 'AuthRelaunch never soft-stops profile'"
  } else { $line }
}
[IO.File]::WriteAllLines($p, $out)
Write-Host 'TEST_UPDATED'
& powershell -NoProfile -ExecutionPolicy Bypass -File $p
Write-Host "EXIT=$LASTEXITCODE"
