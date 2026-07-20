$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $path -Raw
if ($c -notmatch '\$remoteVer = ''''') {
    $c = $c.Replace(
        '    Write-DeployStep "$Label : installing..."',
        "    `$remoteVer = ''`r`n    Write-DeployStep `"`$Label : installing...`""
    )
    Set-Content $path -Value $c -Encoding UTF8
    Write-Host 'init remoteVer'
}
