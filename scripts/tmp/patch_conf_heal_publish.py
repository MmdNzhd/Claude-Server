from pathlib import Path

# PS1
ps = Path(r"D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1")
pt = ps.read_text(encoding="utf-8")
old = '''    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode active_mount=$ActiveMount" 'DEBUG'
    SshX "mkdir -p ~/.local/bin && printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n' '$LaptopUser' '$Port' '$mode' '$am' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf || true" 2>$null | Out-Null
}
'''
new = '''    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode active_mount=$ActiveMount" 'DEBUG'
    SshX "mkdir -p ~/.local/bin && printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n' '$LaptopUser' '$Port' '$mode' '$am' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf || true" 2>$null | Out-Null
    # Win+Mac: server-side self-heal after every conf push (CRLF, git-off, stale mounts)
    SshX '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' 2>$null | Out-Null
}
'''
if old not in pt:
    raise SystemExit('Push-ServerConnectConf block missing')
# Keep Windows CRLF for ps1
ps.write_text(pt.replace(old, new, 1), encoding='utf-8', newline='\r\n')
print('ps1 conf heal OK')

# SH
sh = Path(r"D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh")
st = sh.read_text(encoding="utf-8")
old = '''push_server_connect_conf() {
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    mode="$(get_git_mode)"
    sshx "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=%s\nACTIVE_MOUNT=%s\n' '${LAPTOP_USER}' '$PORT' '${mode}' '${os}' '${active}' > \$HOME/.claude-connect.conf && chmod 600 \$HOME/.claude-connect.conf" 2>/dev/null || true
}
'''
new = '''push_server_connect_conf() {
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    mode="$(get_git_mode)"
    sshx "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=%s\nACTIVE_MOUNT=%s\n' '${LAPTOP_USER}' '$PORT' '${mode}' '${os}' '${active}' > \$HOME/.claude-connect.conf && chmod 600 \$HOME/.claude-connect.conf" 2>/dev/null || true
    # Win+Mac: server-side self-heal after every conf push
    sshx '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' >/dev/null 2>&1 || true
}
'''
if old not in st:
    raise SystemExit('push_server_connect_conf missing')
sh.write_text(st.replace(old, new, 1), encoding='utf-8', newline='\n')
print('sh conf heal OK')

# publish.ps1 - add self-heal + automount to mac and windows package
pub = Path(r"D:\Smart\Claude-Code-Server\publish\publish.ps1")
pt = pub.read_text(encoding="utf-8")
needle = '    @{ Src = "scripts\\server\\claude-mount.sh";           Dst = "mac\\claude-mount.sh";       PatchIp = $false }\r\n)'
if needle not in pt:
    needle = '    @{ Src = "scripts\\server\\claude-mount.sh";           Dst = "mac\\claude-mount.sh";       PatchIp = $false }\n)'
add = '''    @{ Src = "scripts\\server\\claude-mount.sh";           Dst = "mac\\claude-mount.sh";       PatchIp = $false }
    @{ Src = "scripts\\server\\claude-self-heal.sh";       Dst = "mac\\claude-self-heal.sh";   PatchIp = $false }
    @{ Src = "scripts\\server\\claude-automount.sh";       Dst = "mac\\claude-automount.sh";   PatchIp = $false }
    @{ Src = "scripts\\server\\claude-self-heal.sh";       Dst = "windows\\claude-self-heal.sh"; PatchIp = $false }
    @{ Src = "scripts\\server\\claude-automount.sh";       Dst = "windows\\claude-automount.sh"; PatchIp = $false }
)'''
# try flexible replace of the claude-mount line and closing paren
import re
pat = r'(@\{ Src = "scripts\\server\\claude-mount\.sh";\s+Dst = "mac\\claude-mount\.sh";\s+PatchIp = \$false \})\s*\)'
m = re.search(pat, pt)
if not m:
    raise SystemExit('publish mount line not found')
pt2 = pt[:m.start()] + add.strip() + pt[m.end():]
# keep whatever newlines publish uses
pub.write_text(pt2, encoding='utf-8', newline='\r\n')
print('publish.ps1 OK')
print('DONE')
