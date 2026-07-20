$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')

# --- patch deploy hang path by line replace ---
$deploy = Join-Path $root 'publish\deploy-client-bundles.ps1'
$lines = [System.Collections.Generic.List[string]](Get-Content $deploy)
$start = -1; $end = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'installing with stored sudo password \(non-interactive\)') { $start = $i - 1 }
  if ($start -ge 0 -and $lines[$i] -match '^\s*\$ErrorActionPreference = \$prevEap2\s*$') { $end = $i + 1; break }
}
if ($start -lt 0 -or $end -lt 0) { throw "could not find password block start=$start end=$end" }
$replacement = @(
'    if ($sudoExit -ne 0 -and $SudoPassword) {',
'        Write-DeployStep "$Label : installing with stored sudo password (base64, non-interactive)..."',
'        $prevEap2 = $ErrorActionPreference',
'        $ErrorActionPreference = ''SilentlyContinue''',
'        # PowerShell stdin pipe to ssh often hangs/corrupts sudo -S. Embed via base64.',
'        $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SudoPassword))',
'        $remoteInstall = @"',
'set -e',
'PW=`$(printf ''%s'' ''$pwB64'' | base64 -d)',
'python3 -c "from pathlib import Path; p=Path.home()/''$RemoteDeployDir''/''install-client-bundle.sh''; b=p.read_bytes() if p.exists() else b''''; b=b[3:] if b.startswith(b''\xef\xbb\xbf'') else b; p.write_bytes(b.replace(b''\r\n'',b''\n'').replace(b''\r'',b''\n'')) if p.exists() else None" 2>/dev/null || true',
'chmod +x ~/$RemoteDeployDir/install-client-bundle.sh',
'printf ''%s\n'' "`$PW" | sudo -S -p '''' mkdir -p /usr/local/lib/claude-server/commands',
'printf ''%s\n'' "`$PW" | sudo -S -p '''' cp -f ~/$RemoteDeployDir/install-client-bundle.sh /usr/local/lib/claude-server/commands/install-client-bundle.sh',
'printf ''%s\n'' "`$PW" | sudo -S -p '''' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh',
'printf ''%s\n'' "`$PW" | sudo -S -p '''' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip',
'"@',
'        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteInstall))',
'        & ssh -o BatchMode=yes -o ConnectTimeout=90 $ServerTarget "echo $b64 | base64 -d | bash" 2>$null | Out-Null',
'        $sudoExit = $LASTEXITCODE',
'        $ErrorActionPreference = $prevEap2',
'    }'
)
# Fix the replacement - the @" "@ string with $pwB64 needs to be correct PowerShell
# Simpler approach: write a python patcher to avoid escaping hell
Write-Host "Found password block lines $($start+1)-$($end+1)"

$pyPatch = @'
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
'@
$pyPath = Join-Path $env:TEMP 'patch_deploy.py'
# Write py carefully - the nested strings are painful. Use laptop file instead.
Set-Content -Path (Join-Path $root 'scripts\tmp\patch_deploy.py') -Value $pyPatch -Encoding UTF8
python (Join-Path $root 'scripts\tmp\patch_deploy.py')
Write-Host 'deploy patch done'

# --- patch claude-mount ---
$pyMount = @'
from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh")
text = p.read_text(encoding="utf-8")
if "_apply_git_scm_policy" in text:
    print("git scm already present")
else:
    old = '''_warm_sshfs_cache() {
    local lpath="$1"
    if [ -x /usr/local/bin/laptop-exec-setup ]; then
        /usr/local/bin/laptop-exec-setup --project "$lpath" 2>/dev/null || true
    fi
    (
        timeout 5 ls "$lpath/.claude/"          >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/commands/" >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.cursor/rules/"    >/dev/null 2>&1 || true
    ) &
}
'''
    new = '''# GIT_MODE=off|hide: disable Cursor SCM git over SSHFS (avoids "Failed to execute git").
# GIT_MODE=server: leave Cursor git alone.
_apply_git_scm_policy() {
    local lpath="$1"
    [ -n "$lpath" ] && [ -d "$lpath" ] || return 0
    [ "$GIT_MODE" = "server" ] && return 0
    mkdir -p "$lpath/.vscode" 2>/dev/null || return 0
    local settings="$lpath/.vscode/settings.json"
    python3 - "$settings" <<'PY' 2>/dev/null || true
import json, os, sys
path = sys.argv[1]
want = {"git.enabled": False, "git.autoRepositoryDetection": False}
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (OSError, json.JSONDecodeError):
    data = {}
changed = False
for k, v in want.items():
    if data.get(k) != v:
        data[k] = v
        changed = True
if changed or not os.path.isfile(path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\\n")
PY
}

_warm_sshfs_cache() {
    local lpath="$1"
    _apply_git_scm_policy "$lpath"
    if [ -x /usr/local/bin/laptop-exec-setup ]; then
        /usr/local/bin/laptop-exec-setup --project "$lpath" 2>/dev/null || true
    fi
    (
        timeout 5 ls "$lpath/.claude/"          >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/commands/" >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.cursor/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.vscode/"          >/dev/null 2>&1 || true
    ) &
}
'''
    if old not in text:
        raise SystemExit('warm anchor missing')
    p.write_text(text.replace(old, new), encoding='utf-8')
    print('claude-mount patched OK')
'@
Set-Content -Path (Join-Path $root 'scripts\tmp\patch_mount.py') -Value $pyMount -Encoding UTF8
python (Join-Path $root 'scripts\tmp\patch_mount.py')

Write-Host '=== push fixed mount+exec to Sepidz (keep v33, Smart untouched) ==='
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$server = Get-SepidzServerTarget
& scp -o BatchMode=yes -q (Join-Path $root 'scripts\server\claude-mount.sh') "${server}:~/claude-client-bundle-deploy/claude-mount.sh"
& scp -o BatchMode=yes -q (Join-Path $root 'scripts\server\laptop-exec.sh') "${server}:~/claude-client-bundle-deploy/laptop-exec.sh"
& scp -o BatchMode=yes -q (Join-Path $root 'scripts\server\sudoers.d\claude-client-deploy') "${server}:~/claude-client-bundle-deploy/claude-client-deploy.sudoers"
# also refresh bundle mount copy inside share
$remote = @"
set -e
PW=`$(echo $pwB64 | base64 -d)
sp(){ printf '%s\n' "`$PW" | sudo -S -p '' "`$@"; }
python3 - <<'PY'
from pathlib import Path
for name in ['claude-mount.sh','laptop-exec.sh','claude-client-deploy.sudoers']:
 p=Path.home()/'claude-client-bundle-deploy'/name
 if p.exists():
  b=p.read_bytes()
  if b.startswith(b'\xef\xbb\xbf'): b=b[3:]
  p.write_bytes(b.replace(b'\r\n',b'\n').replace(b'\r',b'\n'))
PY
sp cp -f `$HOME/claude-client-bundle-deploy/claude-mount.sh /usr/local/lib/claude-mount
sp cp -f `$HOME/claude-client-bundle-deploy/claude-mount.sh /usr/local/lib/claude-server/claude-mount.sh
sp cp -f `$HOME/claude-client-bundle-deploy/claude-mount.sh /usr/local/share/claude-client/server/claude-mount.sh
sp cp -f `$HOME/claude-client-bundle-deploy/claude-mount.sh /usr/local/share/claude-client/mac/claude-mount.sh
sp cp -f `$HOME/claude-client-bundle-deploy/laptop-exec.sh /usr/local/bin/laptop-exec
sp cp -f `$HOME/claude-client-bundle-deploy/laptop-exec.sh /usr/local/lib/claude-server/laptop-exec.sh
sp cp -f `$HOME/claude-client-bundle-deploy/laptop-exec.sh /usr/local/share/claude-client/server/laptop-exec.sh
sp sed -i 's/\r`$//' /usr/local/bin/laptop-exec /usr/local/lib/claude-mount /usr/local/lib/claude-server/laptop-exec.sh /usr/local/lib/claude-server/claude-mount.sh
sp chmod 755 /usr/local/bin/laptop-exec /usr/local/lib/claude-mount
sp cp -f `$HOME/claude-client-bundle-deploy/claude-client-deploy.sudoers /etc/sudoers.d/claude-client-deploy
sp chmod 440 /etc/sudoers.d/claude-client-deploy
sp visudo -cf /etc/sudoers.d/claude-client-deploy
for h in /home/*; do
  u=`$(basename `$h); id `$u >/dev/null 2>&1 || continue
  sp mkdir -p `$h/.local/bin
  sp cp -f /usr/local/bin/laptop-exec `$h/.local/bin/laptop-exec
  sp chown `$u:`$u `$h/.local/bin/laptop-exec
  sp chmod 755 `$h/.local/bin/laptop-exec
  sp sed -i 's/\r`$//' `$h/.local/bin/laptop-exec
done
grep -q _apply_git_scm_policy /usr/local/lib/claude-mount && echo MOUNT_POLICY=yes || echo MOUNT_POLICY=no
echo VER=`$(cat /usr/local/share/claude-client/connect-version.txt)
"@
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
& ssh -o BatchMode=yes -o ConnectTimeout=120 $server "echo $b64 | base64 -d | bash"
Write-Host "push_exit=$LASTEXITCODE"
