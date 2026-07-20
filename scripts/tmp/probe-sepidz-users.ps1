foreach ($u in @('smart@192.168.250.70','administrator@192.168.250.70','root@192.168.250.70')) {
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','-o','ConnectionAttempts=1',$u,'echo USER_OK; sudo -n true 2>/dev/null; echo sudo_n=$?') -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\probe.out" -RedirectStandardError "$env:TEMP\probe.err"
  Write-Host "$u exit=$($p.ExitCode)"
  Get-Content "$env:TEMP\probe.out" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
}
