from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1")
text = p.read_text(encoding="utf-8")
start = text.find('    if ($sudoExit -ne 0 -and $SudoPassword) {\n        Write-DeployStep "$Label : installing with stored sudo password (non-interactive)..."')
if start < 0:
    start = text.find('installing with stored sudo password (non-interactive)')
    if start < 0:
        raise SystemExit('anchor not found')
    start = text.rfind('\n', 0, start) + 1
    # include the if line
    start = text.rfind('    if ($sudoExit -ne 0 -and $SudoPassword)', 0, start+1)
end_marker = '        $ErrorActionPreference = $prevEap2\n    }\n\n    $remoteVer'
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit('end marker not found')
end = end + len('        $ErrorActionPreference = $prevEap2\n    }')
new = r'''    if ($sudoExit -ne 0 -and $SudoPassword) {
        Write-DeployStep "$Label : installing with stored sudo password (base64, non-interactive)..."
        $prevEap2 = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        # PowerShell stdin pipe to ssh often hangs/corrupts sudo -S. Embed via base64.
        $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SudoPassword))
        $remoteInstall = @"
set -e
PW=$(printf '%s' '$pwB64' | base64 -d)
python3 -c "from pathlib import Path; p=Path.home()/'$RemoteDeployDir'/'install-client-bundle.sh'; b=p.read_bytes() if p.exists() else b''; b=b[3:] if b.startswith(b'\xef\xbb\xbf') else b; p.write_bytes(b.replace(b'\r\n',b'\n').replace(b'\r',b'\n')) if p.exists() else None" 2>/dev/null || true
chmod +x ~/$RemoteDeployDir/install-client-bundle.sh
printf '%s\n' "$PW" | sudo -S -p '' mkdir -p /usr/local/lib/claude-server/commands
printf '%s\n' "$PW" | sudo -S -p '' cp -f ~/$RemoteDeployDir/install-client-bundle.sh /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\n' "$PW" | sudo -S -p '' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\n' "$PW" | sudo -S -p '' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteInstall))
        & ssh -o BatchMode=yes -o ConnectTimeout=90 $ServerTarget "echo $b64 | base64 -d | bash" 2>$null | Out-Null
        $sudoExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap2
    }'''
# In the here-string above, $pwB64 and $RemoteDeployDir and $PW must remain as PowerShell/bash literals.
# Python raw string kept $ as-is. Good.
# But we need `$ for PowerShell escape in @" "@ for $PW - in the remote bash script inside @" "@,
# PowerShell expands $PW unless escaped as `$PW. Fix:
new = new.replace('printf \'%s\\n\' "$PW"', 'printf \'%s\\n\' "`$PW"')
# Wait - in the triple quoted new I used "$PW" - in PowerShell @" "@ that expands. Need `$PW
new = new.replace('printf \'%s\\n\' "`$PW"', 'printf \'%s\\n\' "`$PW"')  # already
# Actually my new uses: printf '%s\n' "$PW"  - in @" "@ $PW expands empty. Must be `$PW
import re
new = re.sub(r'printf \'%s\\n\' "\$PW"', 'printf \'%s\\n\' "`$PW"', new)
# Also PW=$(printf - the $pwB64 in single quotes inside @" is expanded by PS when building remoteInstall - GOOD we want that.
# $RemoteDeployDir in @" is expanded by PS - GOOD.
text2 = text[:start] + new + text[end:]
if 'base64, non-interactive' not in text2:
    raise SystemExit('patch failed to apply')
if '$SudoPassword | & ssh' in text2:
    raise SystemExit('old hang path still present')
p.write_text(text2, encoding='utf-8')
print('deploy-client-bundles patched OK')
