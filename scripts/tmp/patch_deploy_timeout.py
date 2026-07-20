from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1")
t = p.read_text(encoding="utf-8")
old = '''    Write-DeployStep "$Label : installing..."

    # Always try passwordless sudo FIRST (/etc/sudoers.d/claude-client-deploy on Smart).
    # Prefer golden LF installer on server; strip CRLF from uploaded copy as fallback.
    # Never open an interactive password window during publish/agent deploy.
    $sudoExit = 1
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $remoteNopassCmd = @"
python3 -c "from pathlib import Path; p=Path.home()/'$RemoteDeployDir'/'install-client-bundle.sh';
b=p.read_bytes() if p.exists() else b'';
b=b[3:] if b.startswith(b'\\xef\\xbb\\xbf') else b;
p.write_bytes(b.replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n')) if p.exists() else None" 2>/dev/null || true
chmod +x ~/$RemoteDeployDir/install-client-bundle.sh
if [ -x /usr/local/lib/claude-server/commands/install-client-bundle.sh ]; then
  sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
else
  sudo -n /usr/bin/bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
fi
"@
    & ssh -o BatchMode=yes -o ConnectTimeout=30 $ServerTarget $remoteNopassCmd 2>$null | Out-Null
    $sudoExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap

    if ($sudoExit -ne 0 -and $SudoPassword) {
        Write-DeployStep "$Label : installing with stored sudo password (base64, non-interactive)..."
        $prevEap2 = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        # PowerShell stdin pipe to ssh often hangs/corrupts sudo -S. Embed via base64.
        $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SudoPassword))
        $remoteInstall = @"
set -e
PW=$(printf '%s' '$pwB64' | base64 -d)
python3 -c "from pathlib import Path; p=Path.home()/'$RemoteDeployDir'/'install-client-bundle.sh'; b=p.read_bytes() if p.exists() else b''; b=b[3:] if b.startswith(b'\\xef\\xbb\\xbf') else b; p.write_bytes(b.replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n')) if p.exists() else None" 2>/dev/null || true
chmod +x ~/$RemoteDeployDir/install-client-bundle.sh
printf '%s\\n' "`$PW" | sudo -S -p '' mkdir -p /usr/local/lib/claude-server/commands
printf '%s\\n' "`$PW" | sudo -S -p '' cp -f ~/$RemoteDeployDir/install-client-bundle.sh /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\\n' "`$PW" | sudo -S -p '' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\\n' "`$PW" | sudo -S -p '' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteInstall))
        & ssh -o BatchMode=yes -o ConnectTimeout=90 $ServerTarget "echo $b64 | base64 -d | bash" 2>$null | Out-Null
        $sudoExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap2
    }
'''

new = '''    Write-DeployStep "$Label : installing..."

    # Never prompt for sudo password. Prefer stored password (Sepidz) with hard timeout.
    # Passwordless sudo -n only as a short attempt (Smart NOPASSWD); never hang publish.
    function Invoke-SshTimed([string]$Target, [string]$RemoteCmd, [int]$TimeoutSec) {
        $out = [System.IO.Path]::GetTempFileName()
        $err = "$out.err"
        $p = Start-Process -FilePath ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ServerAliveInterval=5','-o','ServerAliveCountMax=3',$Target,$RemoteCmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return 124
        }
        return $p.ExitCode
    }

    $sudoExit = 1
    if ($SudoPassword) {
        Write-DeployStep "$Label : installing with stored sudo password (non-interactive, timed)..."
        $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SudoPassword))
        $remoteInstall = @"
set -e
PW=$(printf '%s' '$pwB64' | base64 -d)
python3 -c "from pathlib import Path; p=Path.home()/'$RemoteDeployDir'/'install-client-bundle.sh'; b=p.read_bytes() if p.exists() else b''; b=b[3:] if b.startswith(b'\\xef\\xbb\\xbf') else b; p.write_bytes(b.replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n')) if p.exists() else None" 2>/dev/null || true
chmod +x ~/$RemoteDeployDir/install-client-bundle.sh
printf '%s\\n' "`$PW" | sudo -S -p '' mkdir -p /usr/local/lib/claude-server/commands
printf '%s\\n' "`$PW" | sudo -S -p '' cp -f ~/$RemoteDeployDir/install-client-bundle.sh /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\\n' "`$PW" | sudo -S -p '' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\\n' "`$PW" | sudo -S -p '' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteInstall))
        $sudoExit = Invoke-SshTimed -Target $ServerTarget -RemoteCmd "echo $b64 | base64 -d | bash" -TimeoutSec 180
    } else {
        Write-DeployStep "$Label : trying passwordless sudo -n (timed 45s)..."
        $remoteNopassCmd = @"
python3 -c "from pathlib import Path; p=Path.home()/'$RemoteDeployDir'/'install-client-bundle.sh'; b=p.read_bytes() if p.exists() else b''; b=b[3:] if b.startswith(b'\\xef\\xbb\\xbf') else b; p.write_bytes(b.replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n')) if p.exists() else None" 2>/dev/null || true
chmod +x ~/$RemoteDeployDir/install-client-bundle.sh
if [ -x /usr/local/lib/claude-server/commands/install-client-bundle.sh ]; then
  sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
else
  sudo -n /usr/bin/bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
fi
"@
        $sudoExit = Invoke-SshTimed -Target $ServerTarget -RemoteCmd $remoteNopassCmd -TimeoutSec 45
    }
'''

# The file uses actual \r in strings differently - read and do a more robust replace by markers
if 'Invoke-SshTimed' in t:
    print('SKIP already patched')
else:
    start = t.find('    Write-DeployStep "$Label : installing..."')
    end = t.find('    $remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $ServerTarget "tr -d')
    if start < 0 or end < 0:
        raise SystemExit(f'markers missing start={start} end={end}')
    t2 = t[:start] + new + '\n\n    ' + t[end:].lstrip()
    # wait, I duplicated - the end line should stay. Fix:
    t2 = t[:start] + new + '\n' + t[end:]
    p.write_text(t2, encoding='utf-8', newline='\n')
    print('OK patched deploy-client-bundles.ps1')
print('DONE')
