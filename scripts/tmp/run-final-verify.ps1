$src='D:\Smart\Claude-Code-Server\scripts\tmp\final-verify-20260717.2.py'
$dst=Join-Path $env:TEMP 'final-verify-20260717.2.py'
Copy-Item -LiteralPath $src -Destination $dst -Force
python $dst
