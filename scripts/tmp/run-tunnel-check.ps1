$ErrorActionPreference = 'Stop'
$src = Join-Path (Get-Location) 'scripts\client\tests\test-server-tunnel-check.sh'
$out = Join-Path $env:TEMP 'tsc-run.sh'
$bytes = [IO.File]::ReadAllBytes($src)
# strip CR
$list = New-Object System.Collections.Generic.List[byte]
foreach ($b in $bytes) { if ($b -ne 13) { [void]$list.Add($b) } }
[IO.File]::WriteAllBytes($out, $list.ToArray())
Write-Host "running $out"
& bash $out
exit $LASTEXITCODE
