$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $path -Raw
$c = $c.Replace(
    '& ssh -o BatchMode=yes -o ConnectTimeout=15 $ServerTarget "sudo -n bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {',
    '$prevEap = $ErrorActionPreference
    $ErrorActionPreference = ''SilentlyContinue''
    & ssh -o BatchMode=yes -o ConnectTimeout=15 $ServerTarget "sudo -n bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip" 2>$null | Out-Null
    $sudoExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($sudoExit -ne 0) {'
)
Set-Content $path -Value $c -Encoding UTF8
Write-Host 'fixed sudo -n error handling'
