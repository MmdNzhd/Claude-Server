$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','smart@192.168.250.70',@'
cd ~/claude-client-bundle-deploy
rm -rf /tmp/bverify && mkdir /tmp/bverify
unzip -q -o bundle.zip -d /tmp/bverify
grep -o "192.168.[0-9.]*" /tmp/bverify/connect.ps1 | head -1
tr -d "\r\n" < /tmp/bverify/connect-version.txt
bash -n /tmp/bverify/mac/claude-mount.sh && echo mount=OK || echo mount=FAIL
'@) -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\bverify.out"
Get-Content "$env:TEMP\bverify.out"
Write-Host "exit=$($p.ExitCode)"
