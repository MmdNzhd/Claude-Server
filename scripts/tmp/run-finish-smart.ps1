$ErrorActionPreference='Stop'
$src='D:\Smart\Claude-Code-Server\scripts\tmp\finish-smart-interactive.py'
$dst=Join-Path $env:TEMP 'finish-smart-interactive.py'
Copy-Item -LiteralPath $src -Destination $dst -Force
python $dst
exit $LASTEXITCODE
