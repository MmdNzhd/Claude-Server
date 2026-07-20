$remoteDay = ".claude/logs/connect-20260719.log"
$cmdString = "cat \"\$HOME/$remoteDay.upload\" >> \"\$HOME/$remoteDay\"; rm -f \"\$HOME/$remoteDay.upload\"; chmod 600 \"\$HOME/$remoteDay\""
Write-Output "RESULT>>>$cmdString<<<RESULT"
