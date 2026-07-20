$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $path -Raw

if ($c -notmatch 'DeploySmart') {
    $c = $c.Replace(
        "[switch]`$ContinueOnDeployError`r`n)",
        "[switch]`$ContinueOnDeployError,`r`n    [switch]`$DeploySmart = `$true,`r`n    [switch]`$DeploySepidz = `$true`r`n)"
    )
    if ($c -notmatch 'DeploySmart') {
        $c = $c.Replace(
            "[switch]`$ContinueOnDeployError`n)",
            "[switch]`$ContinueOnDeployError,`n    [switch]`$DeploySmart = `$true,`n    [switch]`$DeploySepidz = `$true`n)"
        )
    }
    $c = $c.Replace(
        '$targets = @(
    @{ Label = ''Smart'';  Server = $SmartServer;  ClientRoot = $SmartClientRoot }
    @{ Label = ''Sepidz''; Server = $SepidServer; ClientRoot = $SepidClientRoot }
)',
        '$targets = @()
if ($DeploySmart) {
    $targets += @{ Label = ''Smart''; Server = $SmartServer; ClientRoot = $SmartClientRoot }
}
if ($DeploySepidz) {
    $targets += @{ Label = ''Sepidz''; Server = $SepidServer; ClientRoot = $SepidClientRoot }
}
if ($targets.Count -eq 0) { throw ''Nothing to deploy (both -DeploySmart and -DeploySepidz are false)'' }'
    )
    Set-Content $path -Value $c -Encoding UTF8
    Write-Host 'added DeploySmart/DeploySepidz switches'
} else {
    Write-Host 'already has DeploySmart'
}
