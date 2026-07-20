$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\deploy-client-bundles.ps1')).Path
$c = Get-Content $path -Raw
if ($c -notmatch 'ConvertTo-UnixShellScript') {
    $helper = @'

function ConvertTo-UnixShellScript {
    param([Parameter(Mandatory)][string]$SrcPath)
    $bytes = [System.IO.File]::ReadAllBytes($SrcPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
    }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n" -replace "`r", "`n"
    $out = Join-Path $env:TEMP ("unix-" + [IO.Path]::GetFileName($SrcPath))
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($out, $text, $utf8)
    return $out
}

'@
    $c = $c.Replace('function Copy-PublishedFile {', ($helper + 'function Copy-PublishedFile {'))
    $c = $c.Replace(
        '& scp -o BatchMode=yes -o ConnectTimeout=30 -q $InstallScript "${ServerTarget}:~/$RemoteDeployDir/install-client-bundle.sh"',
        '$unixInstall = ConvertTo-UnixShellScript -SrcPath $InstallScript
    & scp -o BatchMode=yes -o ConnectTimeout=30 -q $unixInstall "${ServerTarget}:~/$RemoteDeployDir/install-client-bundle.sh"'
    )
    $c = $c.Replace(
        '        $escaped = $SudoPassword.Replace("'", "'\\''")
        $pwCmd = "bash -lc ""echo ''$escaped'' | sudo -S bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip"""',
        '        $runnerLocal = Join-Path $env:TEMP ("run-install-$Label.sh")
        $runnerText = "#!/bin/bash`nset -e`necho ''$($SudoPassword.Replace("''", "'\''"))'' | sudo -S bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip`n"
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($runnerLocal, $runnerText, $utf8)
        & scp -o BatchMode=yes -o ConnectTimeout=30 -q $runnerLocal "${ServerTarget}:~/$RemoteDeployDir/run-install.sh"
        $pwCmd = "chmod +x ~/$RemoteDeployDir/run-install.sh && bash ~/$RemoteDeployDir/run-install.sh && rm -f ~/$RemoteDeployDir/run-install.sh"'
    )
    Set-Content $path -Value $c -Encoding UTF8
    Write-Host 'patched normalize + run-install upload'
} else {
    Write-Host 'already patched'
}
