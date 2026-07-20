$path = (Resolve-Path (Join-Path $PSScriptRoot '..\client\tests\test-publish.ps1')).Path
$c = Get-Content $path -Raw
if ($c -notmatch 'deploy-client-bundles') {
    $insert = @'

# --- publish -> server deploy integration ---
$deployScript = Join-Path $RepoRoot 'publish\deploy-client-bundles.ps1'
Assert (Test-Path $deployScript) 'deploy-client-bundles.ps1 exists'
$pubRaw = Get-Content (Join-Path $RepoRoot 'publish\publish.ps1') -Raw
Assert ($pubRaw -match '\[switch\]\$SkipServerDeploy') 'publish.ps1 supports -SkipServerDeploy'
Assert ($pubRaw -match 'deploy-client-bundles\.ps1') 'publish.ps1 invokes deploy-client-bundles.ps1'
$depRaw = Get-Content $deployScript -Raw
Assert ($depRaw -match '192\.168\.210\.240') 'deploy script targets Smart server'
Assert ($depRaw -match '192\.168\.250\.70') 'deploy script targets Sepidz server'
$installBundle = Join-Path $RepoRoot 'scripts\server\commands\install-client-bundle.sh'
Assert (Test-Path $installBundle) 'install-client-bundle.sh exists'
$installRaw = Get-Content $installBundle -Raw
Assert ($installRaw -match '_extract_zip') 'install-client-bundle supports python3 zip fallback'

'@
    $c = $c.Replace("Write-Host ''`r`nif (`$fail -eq 0)", ($insert + "Write-Host ''`r`nif (`$fail -eq 0)"))
    if ($c -notmatch '_extract_zip') {
        $c = $c.Replace("Write-Host ''`nif (`$fail -eq 0)", ($insert + "Write-Host ''`nif (`$fail -eq 0)"))
    }
    Set-Content $path -Value $c -Encoding UTF8
    Write-Host 'patched test-publish.ps1'
} else {
    Write-Host 'already patched'
}
