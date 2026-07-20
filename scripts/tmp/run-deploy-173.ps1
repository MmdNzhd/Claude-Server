$ErrorActionPreference='Stop'
$src='D:\Smart\Claude-Code-Server\scripts\tmp\paramiko-deploy-173.py'
$dst=Join-Path $env:TEMP 'paramiko-deploy-173.py'
Copy-Item -LiteralPath $src -Destination $dst -Force
python $dst
exit $LASTEXITCODE
