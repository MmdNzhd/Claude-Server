$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','smart@192.168.250.70','sudo -n true; echo sudo_n=$?') -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\sepid-sudo.out" -RedirectStandardError "$env:TEMP\sepid-sudo.err"
Get-Content "$env:TEMP\sepid-sudo.out" -ErrorAction SilentlyContinue
Write-Host "exit=$($p.ExitCode)"
