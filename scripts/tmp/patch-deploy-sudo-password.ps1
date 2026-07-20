$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $path -Raw

if ($c -notmatch 'Get-DeployCredentials') {
    $c = $c.Replace(
        "Set-StrictMode -Version Latest`r`n`$ErrorActionPreference = 'Stop'",
        "Set-StrictMode -Version Latest`r`n`$ErrorActionPreference = 'Stop'`r`n. (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')"
    )
    if ($c -notmatch 'Get-DeployCredentials') {
        $c = $c.Replace(
            "Set-StrictMode -Version Latest`n`$ErrorActionPreference = 'Stop'",
            "Set-StrictMode -Version Latest`n`$ErrorActionPreference = 'Stop'`n. (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')"
        )
    }
}

$oldParam = @'
        [Parameter(Mandatory)][string]$InstallScript
    )
'@
$newParam = @'
        [Parameter(Mandatory)][string]$InstallScript,
        [string]$SudoPassword = ''
    )
'@
if ($c -notmatch 'SudoPassword') {
    $c = $c.Replace($oldParam, $newParam)
}

$oldInstall = @'
    if ($sudoExit -ne 0) {
        Write-DeployWarn "$Label : sudo password required - opening terminal window..."
'@
$newInstall = @'
    if ($sudoExit -ne 0 -and $SudoPassword) {
        Write-DeployStep "$Label : installing with stored sudo password..."
        $escaped = $SudoPassword.Replace("'", "'\''")
        $pwCmd = "echo '$escaped' | sudo -S bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip"
        $prevEap2 = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        & ssh -o BatchMode=yes -o ConnectTimeout=30 $ServerTarget $pwCmd 2>$null | Out-Null
        $sudoExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap2
        if ($sudoExit -eq 0) {
            $remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $ServerTarget "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
        }
    }
    if ($sudoExit -ne 0 -and -not $remoteVer) {
        Write-DeployWarn "$Label : sudo password required - opening terminal window..."
'@
if ($c -notmatch 'stored sudo password') {
    $c = $c.Replace($oldInstall, $newInstall)
}

$oldCall = 'Invoke-RemoteBundleInstall -ServerTarget $target.Server -Label $target.Label `
            -BundleZip $zipPath -InstallScript $installScript'
$newCall = @'
        $sudoPw = ''
        if ($target.Label -eq 'Sepidz') { $sudoPw = Get-SepidzSudoPassword }
        Invoke-RemoteBundleInstall -ServerTarget $target.Server -Label $target.Label `
            -BundleZip $zipPath -InstallScript $installScript -SudoPassword $sudoPw
'@
if ($c -notmatch 'Get-SepidzSudoPassword') {
    $c = $c.Replace($oldCall, $newCall)
}

Set-Content $path -Value $c -Encoding UTF8
Write-Host 'patched deploy-client-bundles.ps1 for sudo password'
