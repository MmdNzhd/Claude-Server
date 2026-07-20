$ErrorActionPreference='Stop'
$py = 'D:\Smart\Claude-Code-Server\scripts\tmp\paramiko-deploy-sepidz2.py'
$dest = Join-Path $env:TEMP 'paramiko-deploy-sepidz2.py'
Copy-Item -LiteralPath $py -Destination $dest -Force
python $dest
exit $LASTEXITCODE
