from pathlib import Path

# --- Windows connect-update.ps1 ---
win = Path(r"D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1")
w = win.read_text(encoding="utf-8")
old = '''function Get-ServerEndpoint {
    $alias = 'claude-server'
    return @{ Target = $alias; Display = $alias }
}'''
new = '''function Get-LocalServerIp {
    # Prefer ServerIP baked into this package's connect.ps1 (Sepidz vs Smart).
    foreach ($name in @('connect.ps1')) {
        $p = Join-Path $ScriptDir $name
        if (-not (Test-Path $p)) { continue }
        $raw = Get-Content $p -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        $m = [regex]::Match($raw, '(?m)^\\s*\\$ServerIP\\s*=\\s*"([^"]+)"')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    return ''
}

function Find-SshConfigHostForIp {
    param([string]$ServerIp)
    if (-not $ServerIp) { return $null }
    $cfg = Join-Path $env:USERPROFILE '.ssh\\config'
    if (-not (Test-Path $cfg)) { return $null }
    $hostName = $null
    $current = $null
    foreach ($line in Get-Content $cfg) {
        if ($line -match '^\\s*Host\\s+(.+?)\\s*$') {
            $current = ($Matches[1].Trim() -split '\\s+')[0]
            continue
        }
        if (-not $current) { continue }
        if ($line -match '^\\s*HostName\\s+(\\S+)') {
            if ($Matches[1].Trim() -eq $ServerIp) { return $current }
        }
    }
    return $null
}

function Get-ServerEndpoint {
    # NEVER blindly use Host claude-server: on many laptops it points at Smart (210.240)
    # while Sepidz packages must update from 250.70.
    $ip = Get-LocalServerIp
    if ($env:CLAUDE_UPDATE_SSH_TARGET) {
        $t = $env:CLAUDE_UPDATE_SSH_TARGET.Trim()
        return @{ Target = $t; Display = $t }
    }
    if ($ip) {
        $matched = Find-SshConfigHostForIp -ServerIp $ip
        if ($matched) {
            return @{ Target = $matched; Display = "$matched ($ip)" }
        }
        $user = if ($ip -eq '192.168.250.70') { 'sepidz' } elseif ($ip -eq '192.168.210.240') { 'smart' } else { 'smart' }
        $t = "{0}@{1}" -f $user, $ip
        return @{ Target = $t; Display = $t }
    }
    # Last resort (legacy Smart-only laptops)
    return @{ Target = 'claude-server'; Display = 'claude-server' }
}'''
if old not in w:
    raise SystemExit('windows Get-ServerEndpoint block missing')
win.write_text(w.replace(old, new), encoding='utf-8', newline='\n')
print('OK windows connect-update.ps1')

# Also show which target when updating
w2 = win.read_text(encoding='utf-8')
needle = '''$ep = Get-ServerEndpoint
$remoteVer = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/connect-version.txt"
if (-not $remoteVer) {
    Write-UpdateMsg "Client update check skipped (server unreachable or bundle missing)" 'DarkYellow'
    exit 0
}'''
repl = '''$ep = Get-ServerEndpoint
Write-UpdateMsg ("Update source: {0}" -f $ep.Display) 'DarkGray'
$remoteVer = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/connect-version.txt"
if (-not $remoteVer) {
    Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) 'DarkYellow'
    exit 0
}'''
if needle not in w2:
    raise SystemExit('windows update call site missing')
win.write_text(w2.replace(needle, repl), encoding='utf-8', newline='\n')
print('OK windows update source log')

# --- Mac connect-update.sh ---
mac = Path(r"D:\Smart\Claude-Code-Server\scripts\client\mac\connect-update.sh")
m = mac.read_text(encoding='utf-8')
old_m = '''_get_server_target() {
    local server_ip='192.168.210.240' alias='claude-server' remote_user='' cfg
    cfg="$HOME/.config/claude-connect/connect.conf"
    # Prefer saved REMOTE_USER (e.g. smart) — never default to local whoami (Mac laptop user != server user).
    if [ -f "$cfg" ]; then
        remote_user="$(grep -E '^REMOTE_USER=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\\r')"
        local sip
        sip="$(grep -E '^SERVER_IP=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\\r')"
        [ -n "$sip" ] && server_ip="$sip"
    fi
    local ps1="$ROOT_DIR/windows/connect.ps1"
    [ -f "$ps1" ] || ps1="$ROOT_DIR/connect.ps1"
    if [ -f "$ps1" ]; then
        local parsed
        parsed="$(grep -E '^\\$ServerIP\\s*=' "$ps1" 2>/dev/null | head -1 | sed -n 's/.*"\\([^"]*\\)".*/\\1/p')"
        [ -n "$parsed" ] && server_ip="$parsed"
        if [ -z "$remote_user" ]; then
            parsed="$(grep -E '^\\$RemoteUser\\s*=' "$ps1" 2>/dev/null | head -1 | sed -n "s/.*'\\([^']*\\)'.*/\\1/p")"
            [ -n "$parsed" ] && remote_user="$parsed"
        fi
    fi
    # Smart package default
    [ -n "$remote_user" ] || remote_user='smart'
    if [ -f "$HOME/.ssh/config" ] && grep -qE '^Host[[:space:]]+claude-server[[:space:]]*$' "$HOME/.ssh/config" 2>/dev/null; then
        printf '%s\\n' "$alias"
        return
    fi
    printf '%s@%s\\n' "$remote_user" "$server_ip"
}'''

new_m = '''_get_server_target() {
    local server_ip='192.168.210.240' remote_user='' cfg host_alias='' hn
    # Optional override
    if [ -n "${CLAUDE_UPDATE_SSH_TARGET:-}" ]; then
        printf '%s\\n' "$CLAUDE_UPDATE_SSH_TARGET"
        return
    fi
    cfg="$HOME/.config/claude-connect/connect.conf"
    # Prefer saved REMOTE_USER — never default to local whoami (Mac laptop user != server user).
    if [ -f "$cfg" ]; then
        remote_user="$(grep -E '^REMOTE_USER=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\\r')"
        local sip
        sip="$(grep -E '^SERVER_IP=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\\r')"
        [ -n "$sip" ] && server_ip="$sip"
    fi
    local ps1="$ROOT_DIR/windows/connect.ps1" shf="$MAC_DIR/connect.sh"
    [ -f "$ps1" ] || ps1="$ROOT_DIR/connect.ps1"
    if [ -f "$ps1" ]; then
        local parsed
        parsed="$(grep -E '^\\$ServerIP\\s*=' "$ps1" 2>/dev/null | head -1 | sed -n 's/.*"\\([^"]*\\)".*/\\1/p')"
        [ -n "$parsed" ] && server_ip="$parsed"
        if [ -z "$remote_user" ]; then
            parsed="$(grep -E '^\\$RemoteUser\\s*=' "$ps1" 2>/dev/null | head -1 | sed -n "s/.*'\\([^']*\\)'.*/\\1/p")"
            [ -n "$parsed" ] && remote_user="$parsed"
        fi
    fi
    if [ -f "$shf" ]; then
        local parsed
        parsed="$(grep -E '^SERVER_IP=' "$shf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"\\r')"
        [ -n "$parsed" ] && server_ip="$parsed"
    fi
    # Prefer ANY ssh config Host whose HostName matches this package IP (not blind claude-server).
    if [ -f "$HOME/.ssh/config" ]; then
        host_alias=''
        hn=''
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" =~ ^Host[[:space:]]+([^[:space:]]+) ]]; then
                host_alias="${BASH_REMATCH[1]}"
                continue
            fi
            if [[ "$line" =~ ^[[:space:]]*HostName[[:space:]]+([^[:space:]]+) ]]; then
                hn="${BASH_REMATCH[1]}"
                if [ "$hn" = "$server_ip" ] && [ -n "$host_alias" ]; then
                    printf '%s\\n' "$host_alias"
                    return
                fi
            fi
        done < "$HOME/.ssh/config"
    fi
    if [ -z "$remote_user" ]; then
        case "$server_ip" in
            192.168.250.70) remote_user='sepidz' ;;
            *) remote_user='smart' ;;
        esac
    fi
    printf '%s@%s\\n' "$remote_user" "$server_ip"
}'''

# The file may use different escaping - read actual function from file
import re
m2 = re.search(r'_get_server_target\(\) \{.*?\n\}', m, re.S)
if not m2:
    raise SystemExit('mac _get_server_target not found')
# Use new_m but fix double-escaped sequences for real file content
new_m_real = new_m.replace('\\\\n', '\\n').replace('\\\\r', '\\r').replace('\\\\$', '\\$')
# Actually new_m was written with python string - for file we want real \n in printf '%s\n'
new_m_real = r'''_get_server_target() {
    local server_ip='192.168.210.240' remote_user='' cfg host_alias='' hn
    if [ -n "${CLAUDE_UPDATE_SSH_TARGET:-}" ]; then
        printf '%s\n' "$CLAUDE_UPDATE_SSH_TARGET"
        return
    fi
    cfg="$HOME/.config/claude-connect/connect.conf"
    if [ -f "$cfg" ]; then
        remote_user="$(grep -E '^REMOTE_USER=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
        local sip
        sip="$(grep -E '^SERVER_IP=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
        [ -n "$sip" ] && server_ip="$sip"
    fi
    local ps1="$ROOT_DIR/windows/connect.ps1" shf="$MAC_DIR/connect.sh"
    [ -f "$ps1" ] || ps1="$ROOT_DIR/connect.ps1"
    if [ -f "$ps1" ]; then
        local parsed
        parsed="$(grep -E '^\$ServerIP\s*=' "$ps1" 2>/dev/null | head -1 | sed -n 's/.*"\([^"]*\)".*/\1/p')"
        [ -n "$parsed" ] && server_ip="$parsed"
        if [ -z "$remote_user" ]; then
            parsed="$(grep -E '^\$RemoteUser\s*=' "$ps1" 2>/dev/null | head -1 | sed -n "s/.*'\([^']*\)'.*/\1/p")"
            [ -n "$parsed" ] && remote_user="$parsed"
        fi
    fi
    if [ -f "$shf" ]; then
        local parsed
        parsed="$(grep -E '^SERVER_IP=' "$shf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"\r')"
        [ -n "$parsed" ] && server_ip="$parsed"
    fi
    # Prefer ssh Host whose HostName matches this package IP (never blind claude-server→Smart).
    if [ -f "$HOME/.ssh/config" ]; then
        host_alias=''
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" =~ ^Host[[:space:]]+([^[:space:]]+) ]]; then
                host_alias="${BASH_REMATCH[1]}"
                continue
            fi
            if [[ "$line" =~ ^[[:space:]]*HostName[[:space:]]+([^[:space:]]+) ]]; then
                hn="${BASH_REMATCH[1]}"
                if [ "$hn" = "$server_ip" ] && [ -n "$host_alias" ]; then
                    printf '%s\n' "$host_alias"
                    return
                fi
            fi
        done < "$HOME/.ssh/config"
    fi
    if [ -z "$remote_user" ]; then
        case "$server_ip" in
            192.168.250.70) remote_user='sepidz' ;;
            *) remote_user='smart' ;;
        esac
    fi
    printf '%s@%s\n' "$remote_user" "$server_ip"
}'''
mac.write_text(m[:m2.start()] + new_m_real + m[m2.end():], encoding='utf-8', newline='\n')
print('OK mac connect-update.sh')
print('DONE')
