$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $path -Raw

$old = @'
    Write-DeployStep "$Label : installing (sudo password may be prompted)..."
    & ssh -t -o ConnectTimeout=15 $ServerTarget `
        "chmod +x ~/$RemoteDeployDir/install-client-bundle.sh && sudo bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip"
    if ($LASTEXITCODE -ne 0) { throw "Remote install failed for $Label ($ServerTarget)" }

    $remoteVer = & ssh -o BatchMode=yes -o ConnectTimeout=15 $ServerTarget `
        "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt" 2>$null
    if ($remoteVer) {
        Write-DeployOk "$Label deployed v$remoteVer on $ServerTarget"
    } else {
        Write-DeployOk "$Label deployed on $ServerTarget"
    }
}
'@

$new = @'
    $installCmd = "chmod +x ~/$RemoteDeployDir/install-client-bundle.sh && sudo bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip"
    Write-DeployStep "$Label : installing..."

    & ssh -o BatchMode=yes -o ConnectTimeout=15 $ServerTarget "sudo -n bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-DeployWarn "$Label : sudo password required - opening terminal window..."
        $title = "Claude bundle install - $Label"
        Start-Process cmd.exe -ArgumentList @('/k', "title $title && ssh -t -o ConnectTimeout=15 $ServerTarget `"$installCmd`"")
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            $remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $ServerTarget "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
            if ($remoteVer) { break }
        }
        if (-not $remoteVer) {
            throw "Timed out waiting for $Label install (complete sudo in the opened terminal, then re-run publish or finish-sepidz-deploy.bat)"
        }
    } else {
        $remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $ServerTarget "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
    }

    if ($remoteVer) {
        Write-DeployOk "$Label deployed v$remoteVer on $ServerTarget"
    } else {
        throw "Remote install failed for $Label ($ServerTarget)"
    }
}
'@

if ($c -notmatch 'opening terminal window') {
    $c = $c.Replace($old, $new)
    Set-Content $path -Value $c -Encoding UTF8
    Write-Host 'patched deploy-client-bundles.ps1'
} else {
    Write-Host 'already patched'
}
