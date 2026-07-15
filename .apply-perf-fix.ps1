$root = 'D:/Smart/Claude-Code-Server'
$ErrorActionPreference = 'Stop'

function Patch-File {
    param([string]$Path,[string]$Old,[string]$New,[string]$Label)
    if (-not (Test-Path $Path)) { throw "missing $Path" }
    $c = [IO.File]::ReadAllText($Path)
    if ($c.Contains($New.Trim())) { Write-Host "skip $Label (already patched)"; return }
    if (-not $c.Contains($Old)) { throw "pattern missing in $Label" }
    $c = $c.Replace($Old, $New)
    [IO.File]::WriteAllText($Path, $c, (New-Object Text.UTF8Encoding $false))
    Write-Host "ok $Label"
}

$auto = Join-Path $root 'scripts/server/claude-automount.sh'
Patch-File $auto "set -u`n`n# Server-wide OAuth:" "set -u`n`n# Cursor/VS Code spawn bash -ilc to resolve the shell environment. That must not`n# re-run mount/auth/recover (~20s). connect.bat already mounted and synced auth.`nif [ -n `"`${VSCODE_IPC_HOOK_CLI:-}`" ] || [ -n `"`${CURSOR_AGENT:-}`" ] || [ `"`${TERM_PROGRAM:-}`" = `"vscode`" ]; then`n    exit 0`nfi`n`n# Server-wide OAuth:" 'automount-ide-skip'

$c = [IO.File]::ReadAllText($auto)
if (-not $c.Contains('claude-automount.stamp')) {
    $c = $c.Replace('# Restore any .git dirs hidden by a previous crashed session before mounting', "# Throttle full automount on repeated interactive shells (same SSH session).`nSTAMP=`"`$HOME/.cache/claude-automount.stamp`"`nif [ -n `"`${ACTIVE_MOUNT:-}`" ] && [ -f `"`$STAMP`" ]; then`n    stamp_age=`$(( `$(date +%s) - `$(stat -c %Y `"`$STAMP`" 2>/dev/null || echo 0) ))`n    if [ `"`$stamp_age`" -lt 300 ] && `"`$MOUNT_BIN`" check `"`$ACTIVE_MOUNT`" >/dev/null 2>&1; then`n        exit 0`n    fi`nfi`n`n# Restore any .git dirs hidden by a previous crashed session before mounting")
    $c = $c.Replace('    "$MOUNT_BIN" up "$ACTIVE_MOUNT" 2>/dev/null || true`nfi', '    "$MOUNT_BIN" up "$ACTIVE_MOUNT" 2>/dev/null || true`n    mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true`n    touch "$STAMP" 2>/dev/null || true`nfi')
    [IO.File]::WriteAllText($auto, $c, (New-Object Text.UTF8Encoding $false))
    Write-Host 'ok automount-stamp'
}

$mount = Join-Path $root 'scripts/server/claude-mount.sh'
Patch-File $mount '            echo "already mounted: $lpath"`n            _hide_git_and_create_stubs "$rpath"' '            echo "already mounted: $lpath"`n            if [ "${CLAUDE_TRUSTED_TUNNEL:-}" = "1" ] && \`n               { [ ! -e "$lpath/.git" ] || [ -e "$lpath/.git.server-session" ]; } && \`n               [ "$_GIT_HIDE_LAST_FAILED" != "1" ]; then`n                _mount_restore_git_mode`n                return 0`n            fi`n            _hide_git_and_create_stubs "$rpath"' 'claude-mount-fast-path'

$gm = Join-Path $root 'scripts/client/git-mode.ps1'
Patch-File $gm '    Write-GitModeLog "MOUNT_UP begin project=$ProjectId trusted=$TrustedTunnel" ''DEBUG''`n    $swMount = [System.Diagnostics.Stopwatch]::StartNew()' '    Write-GitModeLog "MOUNT_UP begin project=$ProjectId trusted=$TrustedTunnel" ''DEBUG''`n    if (Test-ProjectMountHealthy -ProjectId $ProjectId) {`n        Write-GitModeLog "MOUNT_UP skip project=$ProjectId reason=check_ok" ''DEBUG''`n        if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {`n            Write-ConnectPerfLog -Mark ''mount_total'' -Ms 0 -Extra ''path=skip_check_ok''`n        }`n        return @{ Ok = $true; Out = ''already mounted (check ok)'' }`n    }`n    $swMount = [System.Diagnostics.Stopwatch]::StartNew()' 'git-mode.ps1-mount-skip'

$gms = Join-Path $root 'scripts/client/git-mode.sh'
Patch-File $gms 'invoke_mount_project() {`n    local id="$1" script_dir="${2:-${CONNECT_SCRIPT_DIR:-}}" mount_out="" ec=0 src=""`n    mount_out="$(sshx "CLAUDE_TRUSTED_TUNNEL=1 $CM up ''$id'' 2>&1")"' 'invoke_mount_project() {`n    local id="$1" script_dir="${2:-${CONNECT_SCRIPT_DIR:-}}" mount_out="" ec=0 src=""`n    if project_mount_healthy "$id"; then`n        printf ''already mounted (check ok)''`n        return 0`n    fi`n    mount_out="$(sshx "CLAUDE_TRUSTED_TUNNEL=1 $CM up ''$id'' 2>&1")"' 'git-mode.sh-mount-skip'

foreach ($rel in @('scripts/client/windows/connect.ps1','scripts/client/mac/connect.sh','scripts/client/windows/connect-version.txt')) {
    $p = Join-Path $root $rel
    if (Test-Path $p) {
        $t = [IO.File]::ReadAllText($p).Replace('20260715.6','20260715.7')
        [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding $false))
        Write-Host "ok version $rel"
    }
}
Write-Host 'ALL PATCHES DONE'
