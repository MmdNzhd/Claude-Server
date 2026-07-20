function Invoke-RemoteBundleInstall {
    param(
        [Parameter(Mandatory)][string]$ServerTarget,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$BundleZip,
        [Parameter(Mandatory)][string]$InstallScript,
        [string]$SudoPassword = '',
        [string]$ExpectedVersion = ''
    )

    Write-DeployStep "$Label : uploading bundle to $ServerTarget..."
    & ssh -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no $ServerTarget "mkdir -p ~/$RemoteDeployDir"
    if ($LASTEXITCODE -ne 0) { throw "SSH mkdir failed for $Label ($ServerTarget)" }

    & scp -o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no -q $BundleZip "${ServerTarget}:~/$RemoteDeployDir/bundle.zip"
    if ($LASTEXITCODE -ne 0) { throw "SCP bundle failed for $Label ($ServerTarget)" }

    $instTxt = [IO.File]::ReadAllText($InstallScript).Replace("`r`n", "`n").Replace("`r", "`n")
    $instTmp = Join-Path $env:TEMP ("install-client-bundle-{0}.sh" -f $Label)
    [IO.File]::WriteAllBytes($instTmp, [Text.Encoding]::UTF8.GetBytes($instTxt))
    & scp -o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no -q $instTmp "${ServerTarget}:~/$RemoteDeployDir/install-client-bundle.sh"
    if ($LASTEXITCODE -ne 0) { throw "SCP install script failed for $Label ($ServerTarget)" }

    Write-DeployStep "$Label : installing (non-interactive, timed; never prompts)..."
    if (-not $SudoPassword) {
        throw "$Label : no stored sudo password. Put it in publish/*-deploy.local.ps1. Interactive sudo is disabled."
    }

    function Invoke-SshTimed([string]$Target, [string]$RemoteCmd, [int]$TimeoutSec) {
        $out = [System.IO.Path]::GetTempFileName()
        $err = "$out.err"
        $p = Start-Process -FilePath ssh -ArgumentList @(
            '-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ControlMaster=no',
            '-o','ServerAliveInterval=5','-o','ServerAliveCountMax=12',
            $Target, $RemoteCmd
        ) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return @{ Code = 124; Out = ''; Err = 'TIMEOUT' }
        }
        return @{
            Code = $p.ExitCode
            Out = ((Get-Content $out -Raw -ErrorAction SilentlyContinue) + '')
            Err = ((Get-Content $err -Raw -ErrorAction SilentlyContinue) + '')
        }
    }

    $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SudoPassword))
    $lines = @(
        '#!/bin/bash',
        'set -e',
        ('PW=$(echo {0} | base64 -d)' -f $pwB64),
        ('RD="$HOME/{0}"' -f $RemoteDeployDir),
        'python3 - <<"PY"',
        'from pathlib import Path',
        ('p = Path.home() / "{0}" / "install-client-bundle.sh"' -f $RemoteDeployDir),
        'b = p.read_bytes() if p.exists() else b""',
        'if b.startswith(b"\xef\xbb\xbf"): b = b[3:]',
        'p.write_bytes(b.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))',
        'PY',
        'chmod +x "$RD/install-client-bundle.sh"',
        'printf ''%s\n'' "$PW" | sudo -S -p '''' mkdir -p /usr/local/lib/claude-server/commands',
        'printf ''%s\n'' "$PW" | sudo -S -p '''' cp -f "$RD/install-client-bundle.sh" /usr/local/lib/claude-server/commands/install-client-bundle.sh',
        'printf ''%s\n'' "$PW" | sudo -S -p '''' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh',
        'printf ''%s\n'' "$PW" | sudo -S -p '''' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "$RD/bundle.zip"',
        'ec=$?',
        'echo INSTALL_EC=$ec',
        'exit $ec'
    )
    $wrapPath = Join-Path $env:TEMP ("remote-install-{0}.sh" -f $Label)
    [IO.File]::WriteAllBytes($wrapPath, [Text.Encoding]::UTF8.GetBytes((($lines -join "`n") + "`n")))
    & scp -o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no -q $wrapPath "${ServerTarget}:/tmp/remote-install-$Label.sh"
    if ($LASTEXITCODE -ne 0) { throw "SCP remote install wrap failed for $Label" }

    $res = Invoke-SshTimed -Target $ServerTarget -RemoteCmd "bash /tmp/remote-install-$Label.sh" -TimeoutSec 300
    $sudoExit = [int]$res.Code
    if ($res.Out) { Write-Host $res.Out }
    if ($res.Err -and $res.Err.Trim()) { Write-Host $res.Err }

    $verRes = Invoke-SshTimed -Target $ServerTarget -RemoteCmd "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null" -TimeoutSec 20
    $remoteVer = ($verRes.Out + '').Trim()
    if ($sudoExit -ne 0 -and -not (Test-RemoteVersionMatches -RemoteVer $remoteVer -ExpectedVersion $ExpectedVersion)) {
        throw "$Label : remote sudo install failed (exit=$sudoExit). Expected v$ExpectedVersion, got '$remoteVer'. Fix: publish/*.local.ps1 passwords. No interactive sudo."
    }
    if (-not $remoteVer) {
        throw "Remote install failed for $Label ($ServerTarget): connect-version.txt missing/empty"
    }
    if ($ExpectedVersion -and $remoteVer -ne $ExpectedVersion) {
        throw "Remote version mismatch for $Label ($ServerTarget): expected v$ExpectedVersion, got v$remoteVer"
    }
    Write-DeployOk "$Label deployed v$remoteVer on $ServerTarget"
}

