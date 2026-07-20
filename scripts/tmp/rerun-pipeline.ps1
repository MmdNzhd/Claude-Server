$out = 'D:\Smart\Claude-Code-Server\scripts\tmp\TEST-PIPELINE-OUT.txt'
$script = 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $script *>&1 | Tee-Object -FilePath $out
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }
Add-Content -Path $out -Value ""
Add-Content -Path $out -Value "=== EXIT_CODE=$code ==="
exit $code
