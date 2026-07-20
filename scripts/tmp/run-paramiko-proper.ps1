$ErrorActionPreference='Stop'
$src='D:\Smart\Claude-Code-Server\scripts\tmp\paramiko-deploy-proper.py'
$dst=Join-Path $env:TEMP 'paramiko-deploy-proper.py'
Copy-Item -LiteralPath $src -Destination $dst -Force
python $dst
exit $LASTEXITCODE
