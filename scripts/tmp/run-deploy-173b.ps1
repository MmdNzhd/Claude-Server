$ErrorActionPreference='Stop'
$src='D:\Smart\Claude-Code-Server\scripts\tmp\paramiko-deploy-173b.py'
$dst=Join-Path $env:TEMP 'paramiko-deploy-173b.py'
Copy-Item -LiteralPath $src -Destination $dst -Force
python $dst
exit $LASTEXITCODE
