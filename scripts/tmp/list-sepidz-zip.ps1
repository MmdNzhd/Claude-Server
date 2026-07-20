$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','smart@192.168.250.70','python3 -c "import zipfile; z=zipfile.ZipFile(''/home/smart/claude-client-bundle-deploy/bundle.zip''); print(chr(10).join(sorted(z.namelist())))"') -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\ziplist.out"
Get-Content "$env:TEMP\ziplist.out" | Select-String -Pattern 'mount|mac/|connect.ps1'
Write-Host "--- total lines: $((Get-Content "$env:TEMP\ziplist.out").Count)"
