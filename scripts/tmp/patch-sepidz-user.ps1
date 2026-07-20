$deploy = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $deploy -Raw
$c = $c.Replace("SepidServer = 'smart@192.168.250.70'", "SepidServer = (Get-SepidzServerTarget)")
if ($c -notmatch 'Get-SepidzServerTarget\)') {
    $c = $c.Replace(
        ". (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')",
        ". (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')`r`nif (-not `$PSBoundParameters.ContainsKey('SepidServer')) { `$SepidServer = Get-SepidzServerTarget }"
    )
}
Set-Content $deploy -Value $c -Encoding UTF8

$finish = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\finish-sepidz-deploy.ps1')).Path
$f = Get-Content $finish -Raw
$f = $f.Replace("-SepidServer 'smart@192.168.250.70'", '-SepidServer (Get-SepidzServerTarget)')
if ($f -notmatch 'Get-DeployCredentials') {
    $f = $f.Replace(
        "Set-StrictMode -Version Latest",
        "Set-StrictMode -Version Latest`r`n. (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')"
    )
}
Set-Content $finish -Value $f -Encoding UTF8
Write-Host 'patched sepidz user to sepidz@192.168.250.70'
