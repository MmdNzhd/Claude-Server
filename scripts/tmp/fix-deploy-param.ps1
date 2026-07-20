$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $path -Raw
$c = $c.Replace("[string]`$SepidServer = (Get-SepidzServerTarget),", "[string]`$SepidServer = 'sepidz@192.168.250.70',")
if ($c -notmatch 'PSBoundParameters.ContainsKey\(''SepidServer''\)') {
    $c = $c.Replace(
        ". (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')",
        ". (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')`r`nif (-not `$PSBoundParameters.ContainsKey('SepidServer')) { `$SepidServer = Get-SepidzServerTarget }"
    )
}
Set-Content $path -Value $c -Encoding UTF8
Write-Host 'fixed SepidServer param default'
