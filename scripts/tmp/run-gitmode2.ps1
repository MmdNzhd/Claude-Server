$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $root
$out = Join-Path $root 'scripts\tmp\TEST-GITMODE2-OUT.txt'
$test = Join-Path $root 'scripts\client\tests\test-git-mode-deep.ps1'
if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }
Write-Host "Running $test"
Write-Host "Output  $out"
& $test *>&1 | ForEach-Object {
    $line = "$_"
    Add-Content -LiteralPath $out -Value $line
    Write-Host $line
}
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }
Add-Content -LiteralPath $out -Value "EXIT=$code"
Write-Host "EXIT=$code"
exit $code
