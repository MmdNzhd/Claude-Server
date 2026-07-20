$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','smart@192.168.250.70','id; groups; ls -la /usr/local/share/claude-client 2>&1; ls -la ~/claude-client-bundle-deploy 2>&1') -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\sepid-info.out"
Get-Content "$env:TEMP\sepid-info.out"
Write-Host "exit=$($p.ExitCode)"
