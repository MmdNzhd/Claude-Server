$ErrorActionPreference='Stop'
$env:PYTHONUNBUFFERED='1'
$env:PYTHONIOENCODING='utf-8'
$py = 'D:\Smart\Claude-Code-Server\scripts\tmp\paramiko-deploy-173b.py'
if (-not (Test-Path -LiteralPath $py)) { throw "missing $py" }
python -u $py
exit $LASTEXITCODE
