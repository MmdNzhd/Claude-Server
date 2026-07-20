$ErrorActionPreference = 'Stop'
$repoRoot = Get-Location
$publishPath = Join-Path $repoRoot 'publish\publish.ps1'
$content = Get-Content -LiteralPath $publishPath -Raw

$old = "`r`nif (-not `$SmartOnly) {`r`n}`r`n`r`nWrite-Host `"`"`r`nWrite-Host `"Building Sepidz package (client only, IP patched).`" -ForegroundColor White"
$new = "`r`n}`r`n`r`nif (-not `$SmartOnly) {`r`nWrite-Host `"`"`r`nWrite-Host `"Building Sepidz package (client only, IP patched).`" -ForegroundColor White"

# Normalize to CRLF for matching
$contentNorm = $content -replace "`n", "`r`n"
if ($contentNorm -notmatch 'if \(-not \$SmartOnly\) \{\s*\}') {
    throw 'Empty SmartOnly block not found'
}
$contentNorm = $contentNorm -replace 'if \(-not \$SmartOnly\) \{\s*\}\s*\r?\n\s*\r?\nWrite-Host ""\s*\r?\nWrite-Host "Building Sepidz package', "}`r`n`r`nif (-not `$SmartOnly) {`r`nWrite-Host `"`"`r`nWrite-Host `"Building Sepidz package"

# Remove duplicate closing brace before Done (three braces -> two)
$contentNorm = $contentNorm -replace '(\r?\n    \}\r?\n\})\r?\n\}\r?\n\r?\nWrite-Host ""\r?\nWrite-Host "Done\.', '$1' + "`r`n}`r`n`r`nWrite-Host `"`"`r`nWrite-Host `"Done."

$doneOld = @'
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Main (Smart IP)  : Desktop\claude-publish\$PackageName" -ForegroundColor Green
Write-Host "  Sepidz (IP patch): Desktop\claude-publish\$SepidName" -ForegroundColor Green
if (-not $NoZip) {
    Write-Host "  Main ZIP         : Desktop\claude-publish\$PackageName.zip" -ForegroundColor Green
    Write-Host "  Sepidz ZIP       : Desktop\claude-publish\$SepidName.zip" -ForegroundColor Green
}
'@ -replace "`n", "`r`n"

$doneNew = @'
Write-Host ""
Write-Host "Done." -ForegroundColor Green
if (-not $SepidzOnly) {
    Write-Host "  Main (Smart IP)  : Desktop\claude-publish\$PackageName" -ForegroundColor Green
    if (-not $NoZip) { Write-Host "  Main ZIP         : Desktop\claude-publish\$PackageName.zip" -ForegroundColor Green }
}
if (-not $SmartOnly) {
    Write-Host "  Sepidz (IP patch): Desktop\claude-publish\$SepidName" -ForegroundColor Green
    if (-not $NoZip) { Write-Host "  Sepidz ZIP       : Desktop\claude-publish\$SepidName.zip" -ForegroundColor Green }
}
'@ -replace "`n", "`r`n"

$contentNorm = $contentNorm.Replace($doneOld, $doneNew)

$sepidDeployOld = @'
        & (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
            -ProjectRoot $ProjectRoot `
            -SmartClientRoot $OutDir `
            -SepidClientRoot (Join-Path $SepidDir 'claude-code') `
            -DeploySmart:$false `
            -DeploySepidz:$true
'@ -replace "`n", "`r`n"

$sepidDeployNew = @'
        & (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
            -ProjectRoot $ProjectRoot `
            -SepidClientRoot (Join-Path $SepidDir 'claude-code') `
            -DeploySmart:$false `
            -DeploySepidz:$true
'@ -replace "`n", "`r`n"

$contentNorm = $contentNorm.Replace($sepidDeployOld, $sepidDeployNew)

Set-Content -LiteralPath $publishPath -Value $contentNorm -Encoding UTF8
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($publishPath, [ref]$null, [ref]$errors)
if ($errors) { $errors | ForEach-Object { Write-Host $_.ToString() }; throw 'Syntax errors' }
Write-Host "Fixed $publishPath"
