from pathlib import Path

# --- git-mode.ps1 ---
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1')
c = p.read_text(encoding='utf-8')
old = '''function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = ''
    )
    $mode = $GitMode
    $am = ($ActiveMount -replace "'", "'\\''")
    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode active_mount=$ActiveMount" 'DEBUG'
    SshX "mkdir -p ~/.local/bin && printf 'LAPTOP_USER=%s\\nTUNNEL_PORT=%s\\nGIT_MODE=%s\\nLAPTOP_OS=windows\\nACTIVE_MOUNT=%s\\n' '$LaptopUser' '$Port' '$mode' '$am' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf || true" 2>$null | Out-Null

    # Win+Mac: server-side self-heal after every conf push

    SshX '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' 2>$null | Out-Null
}'''

# Read actual function from file more carefully
import re
m = re.search(r'function Push-ServerConnectConf \{.*?\n\}', c, re.S)
if not m:
    raise SystemExit('Push-ServerConnectConf not found')
print('FOUND len', len(m.group(0)))
print(m.group(0)[:500])
print('---')

new = r'''function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Edge: tunnel-ensure / SSH-setup used to push ACTIVE_MOUNT='' and wipe the
    # server conf mid-session → automount skipped → Cursor opened empty mounts.
    # Preserve existing server ACTIVE_MOUNT unless caller clears or sets explicitly.
    if (-not $ClearActiveMount -and [string]::IsNullOrWhiteSpace($ActiveMount)) {
        $existing = ''
        try {
            $existing = ((SshX "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-") -join '').Trim()
        } catch { }
        if ($existing) {
            $ActiveMount = $existing
        } elseif ($script:ActiveProjectId) {
            $ActiveMount = [string]$script:ActiveProjectId
        }
    }
    if ($ClearActiveMount) { $ActiveMount = '' }
    $am = ($ActiveMount -replace "'", "'\''")
    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode active_mount=$ActiveMount clear=$ClearActiveMount" 'DEBUG'
    SshX "mkdir -p ~/.local/bin && printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n' '$LaptopUser' '$Port' '$mode' '$am' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf || true" 2>$null | Out-Null

    # Win+Mac: server-side self-heal after every conf push

    SshX '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' 2>$null | Out-Null
}'''

c2 = c[:m.start()] + new + c[m.end():]
# CLEAR_MOUNT should explicitly clear
c2 = c2.replace(
    "if ($Port) { Push-ServerConnectConf -ActiveMount '' }",
    "if ($Port) { Push-ServerConnectConf -ClearActiveMount }",
    1
)
# connect.ps1 callers that clear on quit - leave ActiveMount '' but with ClearActiveMount
# those are in connect.ps1 - handle separately
if 'ClearActiveMount' not in c2 or 'Preserve existing server ACTIVE_MOUNT' not in c2:
    raise SystemExit('patch failed markers')
# count ClearActiveMount
print('ClearActiveMount count', c2.count('ClearActiveMount'))
print('preserve comment', 'Preserve existing server ACTIVE_MOUNT' in c2)
p.write_text(c2, encoding='utf-8', newline='\n')
print('git-mode.ps1 patched')

# --- connect.ps1: quit paths should ClearActiveMount ---
cp = Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')
cc = cp.read_text(encoding='utf-8')
n = cc.count("Push-ServerConnectConf -ActiveMount ''")
print('connect.ps1 empty ActiveMount calls', n)
cc2 = cc.replace("Push-ServerConnectConf -ActiveMount ''", "Push-ServerConnectConf -ClearActiveMount")
# bare Push-ServerConnectConf without args is OK now (preserves)
cp.write_text(cc2, encoding='utf-8', newline='\n')
print('connect.ps1 patched', n, 'clear sites')

# --- git-mode.sh ---
sp = Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh')
sc = sp.read_text(encoding='utf-8')
old_sh = '''push_server_connect_conf() {
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    mode="$(get_git_mode)"
    sshx "printf 'LAPTOP_USER=%s\\nTUNNEL_PORT=%s\\nGIT_MODE=%s\\nLAPTOP_OS=%s\\nACTIVE_MOUNT=%s\\n' '${LAPTOP_USER}' '$PORT' '${mode}' '${os}' '${active}' > \\$HOME/.claude-connect.conf && chmod 600 \\$HOME/.claude-connect.conf" 2>/dev/null || true
    # Win+Mac: server-side self-heal after every conf push
    sshx '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' >/dev/null 2>&1 || true
}'''
# find actual
m2 = re.search(r'push_server_connect_conf\(\) \{.*?\n\}', sc, re.S)
if not m2:
    raise SystemExit('push_server_connect_conf not found')
print('sh found', m2.group(0)[:300])
new_sh = r'''push_server_connect_conf() {
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    local clear="${1:-}"
    mode="$(get_git_mode)"
    # Preserve server ACTIVE_MOUNT when caller left it empty (tunnel-ensure must not wipe).
    if [ "$clear" != "--clear" ] && [ -z "$active" ]; then
        active="$(sshx "grep -E '^ACTIVE_MOUNT=' \$HOME/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-" 2>/dev/null | tr -d '\r' || true)"
        [ -z "$active" ] && active="${ACTIVE_PROJECT_ID:-}"
    fi
    if [ "$clear" = "--clear" ]; then active=""; fi
    sshx "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=%s\nACTIVE_MOUNT=%s\n' '${LAPTOP_USER}' '$PORT' '${mode}' '${os}' '${active}' > \$HOME/.claude-connect.conf && chmod 600 \$HOME/.claude-connect.conf" 2>/dev/null || true
    # Win+Mac: server-side self-heal after every conf push
    sshx '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' >/dev/null 2>&1 || true
}'''
sc2 = sc[:m2.start()] + new_sh + sc[m2.end():]
# clear_mount sets ACTIVE_MOUNT_ID="" then push - change to push --clear
# Find: ACTIVE_MOUNT_ID=""\n    push_server_connect_conf
sc2 = sc2.replace(
    'ACTIVE_MOUNT_ID=""\n    push_server_connect_conf\n}',
    'ACTIVE_MOUNT_ID=""\n    push_server_connect_conf --clear\n}',
    1
)
sp.write_text(sc2, encoding='utf-8', newline='\n')
print('git-mode.sh patched')
print('DONE')
