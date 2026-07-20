$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

Write-Host '=== 1) Patch deploy-client-bundles hang path ==='
$deploy = Join-Path $root 'publish\deploy-client-bundles.ps1'
$raw = [IO.File]::ReadAllText($deploy)
if ($raw -match 'base64, non-interactive') {
  Write-Host 'deploy password path already base64'
} else {
  $old = @'
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
  $new = @'
    if ($sudoExit -ne 0 -and $SudoPassword) {
        Write-DeployStep "$Label : installing with stored sudo password (base64, non-interactive)..."
        $prevEap2 = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        # PowerShell stdin pipe to ssh often hangs/corrupts sudo -S. Embed via base64.
        $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SudoPassword))
        $remoteInstall = @"
set -e
PW=`$(printf '%s' '$pwB64' | base64 -d)
python3 -c "from pathlib import Path; p=Path.home()/'$RemoteDeployDir'/'install-client-bundle.sh'; b=p.read_bytes() if p.exists() else b''; b=b[3:] if b.startswith(b'\\xef\\xbb\\xbf') else b; p.write_bytes(b.replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n')) if p.exists() else None" 2>/dev/null || true
chmod +x ~/$RemoteDeployDir/install-client-bundle.sh
mkdir -p /tmp
cat > /tmp/claude-client-deploy.sudoers <<'S'
Defaults:smart !requiretty
Defaults:sepidz !requiretty
Cmnd_Alias CLAUDE_CLIENT_BUNDLE = /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh *, /bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh *, /usr/bin/bash /home/smart/claude-client-bundle-deploy/install-client-bundle.sh *, /bin/bash /home/smart/claude-client-bundle-deploy/install-client-bundle.sh *, /usr/bin/bash /home/sepidz/claude-client-bundle-deploy/install-client-bundle.sh *, /bin/bash /home/sepidz/claude-client-bundle-deploy/install-client-bundle.sh *
smart ALL=(root) NOPASSWD: CLAUDE_CLIENT_BUNDLE
sepidz ALL=(root) NOPASSWD: CLAUDE_CLIENT_BUNDLE
S
printf '%s\n' "`$PW" | sudo -S -p '' mkdir -p /usr/local/lib/claude-server/commands
printf '%s\n' "`$PW" | sudo -S -p '' cp -f ~/$RemoteDeployDir/install-client-bundle.sh /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\n' "`$PW" | sudo -S -p '' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh
printf '%s\n' "`$PW" | sudo -S -p '' cp -f /tmp/claude-client-deploy.sudoers /etc/sudoers.d/claude-client-deploy
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
  if (-not $raw.Contains($old)) { throw 'deploy password anchor not found' }
  [IO.File]::WriteAllText($deploy, $raw.Replace($old, $new))
  Write-Host 'patched deploy-client-bundles.ps1'
}

Write-Host '=== 2) Patch Build-AutoUpdateBundleStage repo layout ==='
$raw2 = [IO.File]::ReadAllText($deploy)
if ($raw2 -match 'also tried client root') {
  Write-Host 'stage resolve already patched'
} else {
  $oldB = @'
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
  $newB = @'
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
  if (-not $raw2.Contains($oldB)) { Write-Host 'WARN stage anchor missing'; }
  else {
    [IO.File]::WriteAllText($deploy, $raw2.Replace($oldB, $newB))
    Write-Host 'patched stage resolve'
  }
}

Write-Host '=== 3) Patch claude-mount git SCM policy ==='
$mount = Join-Path $root 'scripts\server\claude-mount.sh'
$mraw = [IO.File]::ReadAllText($mount)
if ($mraw -match '_apply_git_scm_policy') {
  Write-Host 'git scm policy already present'
} else {
  $oldW = @'
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
  $newW = @'
# GIT_MODE=off|hide: disable Cursor SCM git over SSHFS (avoids "Failed to execute git").
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
  if (-not $mraw.Contains($oldW)) { throw 'claude-mount warm anchor missing' }
  [IO.File]::WriteAllText($mount, $mraw.Replace($oldW, $newW))
  Write-Host 'patched claude-mount git scm policy'
}

Write-Host '=== 4) Ensure sudoers template dual smart+sepidz ==='
$sudoers = Join-Path $root 'scripts\server\sudoers.d\claude-client-deploy'
$s = @'
# Allow Smart + Sepidz deploy without interactive password (client auto-update bundle).
Defaults:smart !requiretty
Defaults:sepidz !requiretty
Cmnd_Alias CLAUDE_CLIENT_BUNDLE = /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh *, /bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh *, /usr/bin/bash /home/smart/claude-client-bundle-deploy/install-client-bundle.sh *, /bin/bash /home/smart/claude-client-bundle-deploy/install-client-bundle.sh *, /usr/bin/bash /home/sepidz/claude-client-bundle-deploy/install-client-bundle.sh *, /bin/bash /home/sepidz/claude-client-bundle-deploy/install-client-bundle.sh *
smart ALL=(root) NOPASSWD: CLAUDE_CLIENT_BUNDLE
sepidz ALL=(root) NOPASSWD: CLAUDE_CLIENT_BUNDLE
'@
[IO.File]::WriteAllText($sudoers, $s.Replace("`r`n","`n"))
Write-Host 'sudoers template written'

# Keep version at 33 for Sepidz; do NOT touch Smart (22)
$ver = (Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
Write-Host "REPO_VERSION=$ver"
if ($ver -ne '20260717.33') {
  . (Join-Path $root 'publish\bump-connect-version.ps1')
  Set-ConnectVersionInRepo -ProjectRoot $root -Version '20260717.33'
  Write-Host 'forced repo back to 20260717.33'
}

Write-Host 'GAPS_CLOSED'
