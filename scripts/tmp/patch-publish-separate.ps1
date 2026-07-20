$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\publish.ps1')).Path
$c = Get-Content $path -Raw

# 1. Add SmartOnly / SepidzOnly params
if ($c -notmatch 'SmartOnly') {
    $c = $c.Replace(
        "[switch]`$SkipServerDeploy`r`n)",
        "[switch]`$SkipServerDeploy,`r`n    [switch]`$SmartOnly,`r`n    [switch]`$SepidzOnly`r`n)"
    )
    if ($c -notmatch 'SmartOnly') {
        $c = $c.Replace(
            "[switch]`$SkipServerDeploy`n)",
            "[switch]`$SkipServerDeploy,`n    [switch]`$SmartOnly,`n    [switch]`$SepidzOnly`n)"
        )
    }
}

# 2. Wrap Smart package build start
if ($c -notmatch 'SepidzOnly\) \{') {
    $c = $c.Replace(
        'Write-Host ""`r`nWrite-Host "Publishing $PackageName (client only)" -ForegroundColor White',
        'if ($SmartOnly -and $SepidzOnly) { throw ''Use only one of -SmartOnly or -SepidzOnly'' }`r`n`r`nWrite-Host ""`r`nif ($SepidzOnly) {`r`n    Write-Host "Publishing $SepidName (Sepidz only)" -ForegroundColor White`r`n} else {`r`n    Write-Host "Publishing $PackageName (client only)" -ForegroundColor White`r`n}'
    )
    $c = $c.Replace(
        'Write-Step "Creating output folder..."',
        'if (-not $SepidzOnly) {`r`nWrite-Step "Creating output folder..."'
    )
    # Close Smart-only block before Sepidz section
    $c = $c.Replace(
        'Write-Host ""`r`nWrite-Host "Building Sepidz package (client only, IP patched)..." -ForegroundColor White',
        '}`r`n`r`nif (-not $SmartOnly) {`r`nWrite-Host ""`r`nWrite-Host "Building Sepidz package (client only, IP patched)..." -ForegroundColor White'
    )
    # Close Sepidz block before combined deploy removal - before final deploy block
    $c = $c.Replace(
        'if (-not $SkipServerDeploy) {`r`n    Write-Host ""`r`n    Write-Host "Deploying client bundles to Smart + Sepidz servers..."',
        '}`r`n`r`n# per-package deploy happens inline above`r`nif ($false -and -not $SkipServerDeploy) {`r`n    Write-Host ""`r`n    Write-Host "Deploying client bundles to Smart + Sepidz servers..."'
    )
}

Set-Content $path -Value $c -Encoding UTF8
Write-Host 'phase1 publish.ps1 params+wrap (partial)'
