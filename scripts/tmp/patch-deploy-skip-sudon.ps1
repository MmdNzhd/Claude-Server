$ErrorActionPreference='Stop'
$p = (Resolve-Path 'publish\deploy-client-bundles.ps1').Path
$raw = [IO.File]::ReadAllText($p)
$nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
$c = $raw -replace "`r`n","`n" -replace "`r","`n"

$old = @'
    Write-DeployStep "$Label : installing..."
    # Prefer passwordless sudo; fall back to local password helper if configured.
    & ssh -o BatchMode=yes -o ConnectTimeout=15 $ServerTarget "sudo -n bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip" 2>$null | Out-Null
    $sudoExit = $LASTEXITCODE

    if ($sudoExit -ne 0 -and $SudoPassword) {
'@

$new = @'
    Write-DeployStep "$Label : installing..."
    # Prefer password path when available — sudo -n over flaky SSH often hangs and never falls back.
    $sudoExit = 1
    if (-not $SudoPassword) {
        & ssh -o BatchMode=yes -o ConnectTimeout=8 $ServerTarget "sudo -n bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip" 2>$null | Out-Null
        $sudoExit = $LASTEXITCODE
    }

    if ($sudoExit -ne 0 -and $SudoPassword) {
'@

$oldN = $old -replace "`r`n","`n"
$newN = $new -replace "`r`n","`n"
if ($c.IndexOf($oldN) -lt 0) { throw 'install block pattern missing' }
$c2 = $c.Replace($oldN, $newN)
if ($nl -eq "`r`n") { $c2 = $c2 -replace "`n","`r`n" }
[IO.File]::WriteAllText($p, $c2)
Write-Host 'OK patched deploy-client-bundles sudo path'
