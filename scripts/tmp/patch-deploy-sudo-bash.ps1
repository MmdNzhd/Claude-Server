$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $path -Raw

$c = $c.Replace("SepidServer = 'smart@192.168.250.70'", "SepidServer = 'sepidz@192.168.250.70'")
$c = $c.Replace("SepidServer = (Get-SepidzServerTarget)", "SepidServer = 'sepidz@192.168.250.70'")

$old = @'
        $escaped = $SudoPassword.Replace("'", "'\''")
        $pwCmd = "echo '$escaped' | sudo -S bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip"
        $prevEap2 = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        & ssh -o BatchMode=yes -o ConnectTimeout=30 $ServerTarget $pwCmd 2>$null | Out-Null
'@
$new = @'
        $escaped = $SudoPassword.Replace("'", "'\\''")
        $pwCmd = "bash -lc ""echo '$escaped' | sudo -S bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip"""
        $prevEap2 = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        & ssh -o BatchMode=yes -o ConnectTimeout=120 $ServerTarget $pwCmd 2>$null | Out-Null
'@
if ($c -match 'echo ''\$escaped'' \| sudo -S bash') {
    $c = $c.Replace($old, $new)
}

if ($c -notmatch 'Get-SepidzServerTarget') {
    $c = $c.Replace(
        ". (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')",
        ". (Join-Path `$PSScriptRoot 'Get-DeployCredentials.ps1')`r`nif (-not `$PSBoundParameters.ContainsKey('SepidServer')) { `$SepidServer = Get-SepidzServerTarget }"
    )
}

Set-Content $path -Value $c -Encoding UTF8
Write-Host 'patched deploy sudo + sepidz user default'
