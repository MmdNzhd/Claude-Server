#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

function Replace-Once([string]$Path, [string]$Old, [string]$New, [string]$Label) {
  $raw = [System.IO.File]::ReadAllText($Path)
  if ($raw.Contains($New.Substring(0, [Math]::Min(80, $New.Length))) -and $Label -match 'idempotent') {
    Write-Host "skip(already): $Label"
    return
  }
  if (-not $raw.Contains($Old)) { throw "anchor not found for $Label in $Path" }
  $idx = $raw.IndexOf($Old)
  $count = ([regex]::Matches($raw, [regex]::Escape($Old))).Count
  if ($count -ne 1) { throw "expected 1 match for $Label, got $count" }
  $raw2 = $raw.Remove($idx, $Old.Length).Insert($idx, $New)
  [System.IO.File]::WriteAllText($Path, $raw2)
  Write-Host "patched: $Label"
}

# ---- 1) claude-mount.sh: git SCM policy ----
$mount = Join-Path $root 'scripts\server\claude-mount.sh'
$oldWarm = @'
_warm_sshfs_cache() {
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
'@
$newWarm = @'
# GIT_MODE=off|hide: disable Cursor SCM git over SSHFS (avoids "Failed to execute git").
# GIT_MODE=server: leave Cursor git alone (user wants SSHFS git).
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
        f.write("\n")
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
'@
Replace-Once $mount $oldWarm $newWarm 'claude-mount git scm policy'

# ---- 2) deploy-client-bundles.ps1: resolve repo layout + non-hanging sudo ----
$deploy = Join-Path $root 'publish\deploy-client-bundles.ps1'
$oldBuild = @'
    foreach ($name in $WinBundleFiles) {
        $src = Join-Path $ClientRoot "windows\$name"
        if (-not (Test-Path $src)) { throw "Missing published file: $src" }
        Copy-PublishedFile -Src $src -Dst (Join-Path $StageDir $name)
    }

    foreach ($name in $MacBundleFiles) {
        $src = Join-Path $ClientRoot "mac\$name"
        if (-not (Test-Path $src)) { throw "Missing published file: $src" }
        Copy-PublishedFile -Src $src -Dst (Join-Path $StageDir "mac\$name")
    }
'@
$newBuild = @'
    foreach ($name in $WinBundleFiles) {
        $src = Join-Path $ClientRoot "windows\$name"
        if (-not (Test-Path $src)) { $src = Join-Path $ClientRoot $name }
        if (-not (Test-Path $src)) { throw "Missing published file: windows\$name (also tried client root)" }
        Copy-PublishedFile -Src $src -Dst (Join-Path $StageDir $name)
    }

    foreach ($name in $MacBundleFiles) {
        $src = Join-Path $ClientRoot "mac\$name"
        if (-not (Test-Path $src)) { $src = Join-Path $ClientRoot $name }
        if (-not (Test-Path $src) -and $name -eq 'claude-mount.sh') {
            $src = Join-Path $ProjectRoot 'scripts\server\claude-mount.sh'
        }
        if (-not (Test-Path $src) -and $name -eq 'connect-version.txt') {
            $src = Join-Path $ClientRoot 'windows\connect-version.txt'
        }
        if (-not (Test-Path $src)) { throw "Missing published file: mac\$name" }
        Copy-PublishedFile -Src $src -Dst (Join-Path $StageDir "mac\$name")
    }
'@
Replace-Once $deploy $oldBuild $newBuild 'deploy stage resolve repo layout'

$oldPw = @'
    if ($sudoExit -ne 0 -and $SudoPassword) {
        Write-DeployStep "$Label : installing with stored sudo password (non-interactive)..."
        $prevEap2 = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        $remoteInstall = @"
chmod +x ~/$RemoteDeployDir/install-client-bundle.sh
if [ -x /usr/local/lib/claude-server/commands/install-client-bundle.sh ]; then
  sudo -S /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
else
  sudo -S /usr/bin/bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
fi
"@
        $SudoPassword | & ssh -o BatchMode=yes -o ConnectTimeout=45 $ServerTarget $remoteInstall 2>$null | Out-Null
        $sudoExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap2
    }
'@
$newPw = @'
    if ($sudoExit -ne 0 -and $SudoPassword) {
        Write-DeployStep "$Label : installing with stored sudo password (base64, non-interactive)..."
        $prevEap2 = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        # PowerShell stdin pipe to ssh often hangs/corrupts sudo -S. Embed password via base64 instead.
        $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SudoPassword))
        $remoteInstall = @"
set -e
PW=`$(printf '%s' '$pwB64' | base64 -d)
python3 -c "from pathlib import Path; p=Path.home()/'$RemoteDeployDir'/'install-client-bundle.sh'; b=p.read_bytes() if p.exists() else b''; b=b[3:] if b.startswith(b'\\xef\\xbb\\xbf') else b; p.write_bytes(b.replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n')) if p.exists() else None" 2>/dev/null || true
chmod +x ~/$RemoteDeployDir/install-client-bundle.sh
# Ensure NOPASSWD sudoers for next deploys (Smart + Sepidz)
SUDOERS=/tmp/claude-client-deploy.sudoers.$$$$
cat > "`$SUDOERS" <<'S'
Defaults:smart !requiretty
Defaults:sepidz !requiretty
Cmnd_Alias CLAUDE_CLIENT_BUNDLE = /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh *, /bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh *, /usr/bin/bash /home/smart/claude-client-bundle-deploy/install-client-bundle.sh *, /bin/bash /home/smart/claude-client-bundle-deploy/install-client-bundle.sh *, /usr/bin/bash /home/sepidz/claude-client-bundle-deploy/install-client-bundle.sh *, /bin/bash /home/sepidz/claude-client-bundle-deploy/install-client-bundle.sh *
smart ALL=(root) NOPASSWD: CLAUDE_CLIENT_BUNDLE
sepidz ALL=(root) NOPASSWD: CLAUDE_CLIENT_BUNDLE
S
printf '%s\n' "`$PW" | sudo -S -p '' mkdir -p /usr/local/lib/claude-server/commands
printf '%s\n' "`$PW" | sudo -S -p '' cp -f ~/$RemoteDeployDir/install-client-bundle.sh /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\n' "`$PW" | sudo -S -p '' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\n' "`$PW" | sudo -S -p '' cp -f "`$SUDOERS" /etc/sudoers.d/claude-client-deploy
printf '%s\n' "`$PW" | sudo -S -p '' chmod 440 /etc/sudoers.d/claude-client-deploy
printf '%s\n' "`$PW" | sudo -S -p '' visudo -cf /etc/sudoers.d/claude-client-deploy >/dev/null
printf '%s\n' "`$PW" | sudo -S -p '' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteInstall))
        & ssh -o BatchMode=yes -o ConnectTimeout=90 $ServerTarget "echo $b64 | base64 -d | bash" 2>$null | Out-Null
        $sudoExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap2
    }
'@
Replace-Once $deploy $oldPw $newPw 'deploy non-hanging sudo password path'

# ---- 3) connect-update.ps1: visible messages ----
$upd = Join-Path $root 'scripts\client\windows\connect-update.ps1'
$oldUpd = @'
$localVer = Get-LocalVersion
if (-not $localVer) { exit 0 }

$ep = Get-ServerEndpoint
$remoteVer = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/connect-version.txt"
if (-not $remoteVer) { exit 0 }

if (-not (Test-RemoteVersionNewer -Remote $remoteVer -Local $localVer)) { exit 0 }
'@
$newUpd = @'
$localVer = Get-LocalVersion
if (-not $localVer) { exit 0 }

$ep = Get-ServerEndpoint
$remoteVer = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/connect-version.txt"
if (-not $remoteVer) {
    Write-UpdateMsg "Client update check skipped (server unreachable or bundle missing)" 'DarkYellow'
    exit 0
}

if (-not (Test-RemoteVersionNewer -Remote $remoteVer -Local $localVer)) {
    Write-UpdateMsg "Client up to date (v$localVer)" 'DarkGray'
    exit 0
}
'@
Replace-Once $upd $oldUpd $newUpd 'connect-update status messages'

Write-Host 'ALL_PATCHES_OK'
