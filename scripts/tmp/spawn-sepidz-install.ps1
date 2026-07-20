$cmd = 'ssh -t smart@192.168.250.70 "chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh && sudo bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip && echo DONE && pause"'
Start-Process cmd.exe -ArgumentList "/k $cmd"
Write-Host "Spawned interactive CMD for Sepidz sudo install"
Start-Sleep -Seconds 3
