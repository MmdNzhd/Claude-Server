# -*- coding: utf-8 -*-
from pathlib import Path

def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'MISS {label}')
    if text.count(old) != 1:
        # allow if unique enough
        pass
    n = text.replace(old, new, 1)
    if n == text:
        raise SystemExit(f'NOCHANGE {label}')
    print('OK', label)
    return n

# ---- connect-ui.ps1 ----
p = Path('scripts/client/connect-ui.ps1')
t = p.read_text(encoding='utf-8')

helpers = r'''
function Get-ConnectSessionId {
    if ($script:ConnectSessionId -and $script:ConnectSessionId.Trim().Length -ge 4) {
        return $script:ConnectSessionId.Trim()
    }
    if ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
        $script:ConnectSessionId = $env:CLAUDE_CONNECT_RUN_ID.Trim()
    } else {
        $script:ConnectSessionId = [guid]::NewGuid().ToString('N').Substring(0, 12)
    }
    $env:CLAUDE_CONNECT_RUN_ID = $script:ConnectSessionId
    return $script:ConnectSessionId
}

function Write-ConnectSessionIndex {
    param(
        [string]$Phase = 'start',
        [string]$Version = '',
        [string]$Project = '-'
    )
    try {
        $sid = Get-ConnectSessionId
        $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
        $null = New-Item -ItemType Directory -Force -Path $dir
        $idx = Join-Path $dir 'sessions.index'
        $ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff'
        $hostName = try { [System.Net.Dns]::GetHostName() } catch { $env:COMPUTERNAME }
        $ver = if ($Version) { $Version } elseif ($script:ConnectVersion) { $script:ConnectVersion } else { '-' }
        $proj = if ($Project) { $Project } else { '-' }
        $line = "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}" -f $ts, $sid, $PID, $env:USERNAME, $hostName, $ver, $Phase, $proj
        [System.IO.File]::AppendAllText($idx, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

'''

if 'function Get-ConnectSessionId' not in t:
    t = replace_once(t, 'function Initialize-ConnectLog {', helpers + 'function Initialize-ConnectLog {', 'ps1 helpers')

old_init_sid = '''    if (-not $script:ConnectSessionId) {
        if ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
            $script:ConnectSessionId = $env:CLAUDE_CONNECT_RUN_ID.Trim()
        } else {
            $script:ConnectSessionId = [guid]::NewGuid().ToString('N').Substring(0, 12)
        }
    }
'''
new_init_sid = '''    $null = Get-ConnectSessionId
    $env:CLAUDE_CONNECT_RUN_ID = $script:ConnectSessionId
'''
if old_init_sid in t:
    t = replace_once(t, old_init_sid, new_init_sid, 'ps1 init sid')

old_start = '''    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID session=$($script:ConnectSessionId) ========"
    Write-ConnectLog "log sink: local:$($script:ConnectLogPath) watermark=$($script:ConnectLogSyncOffset) + server:~/.claude/logs/ (nightly purge)"
    Write-ConnectLog "script_dir: $ScriptDir connect_version: $Version" 'DEBUG'
    $script:ConnectUiReady = $true
}
'''
new_start = '''    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID session=$($script:ConnectSessionId) ========"
    Write-ConnectLog "log sink: local:$($script:ConnectLogPath) watermark=$($script:ConnectLogSyncOffset) + server:~/.claude/logs/ (nightly purge)"
    Write-ConnectLog "script_dir: $ScriptDir connect_version: $Version" 'DEBUG'
    Write-ConnectLog ("SESSION_FILTER grep=[{0}] tip=filter day log by bracketed session id" -f $script:ConnectSessionId)
    Write-ConnectSessionIndex -Phase 'start' -Version $Version
    $script:ConnectUiReady = $true
}
'''
if old_start in t:
    t = replace_once(t, old_start, new_start, 'ps1 session filter')

# index on context
if 'Write-ConnectSessionIndex -Phase $Phase' not in t:
    old_ctx = '    Write-ConnectLog "======== CONTEXT phase=$Phase ========"\n'
    new_ctx = '    Write-ConnectSessionIndex -Phase $Phase -Project $am\n    Write-ConnectLog "======== CONTEXT phase=$Phase ========"\n'
    if old_ctx in t:
        t = replace_once(t, old_ctx, new_ctx, 'ps1 context index')

p.write_text(t, encoding='utf-8', newline='\n')

# ---- connect.ps1 TUNNEL_DROP ----
cp = Path('scripts/client/windows/connect.ps1')
ct = cp.read_text(encoding='utf-8')
old_drop = """                    $action = 'r'
                    Write-ConnectLog 'TUNNEL: connection dropped - auto reconnect' 'WARN'
                    Write-Host \"    Connection dropped - reconnecting...\" -ForegroundColor Yellow
"""
new_drop = """                    $action = 'r'
                    $sf = if ($null -ne $script:TunnelSoftFailCount) { $script:TunnelSoftFailCount } else { '?' }
                    $tcp = if (Get-Command Test-TunnelUp -ErrorAction SilentlyContinue) { [bool](Test-TunnelUp) } else { '?' }
                    $proj = if ($go -and $go.Id) { $go.Id } else { '?' }
                    Write-ConnectLog (\"TUNNEL_DROP reason=auto_reconnect soft_fail={0} tcp_up={1} tunnel_sync_ok={2} project={3} editor_opened={4} editor_seen={5} gen={6}\" -f $sf, $tcp, $tunnelSyncOk, $proj, $editorOpened, $script:EditorSeenOpen, $script:RecoveryGeneration) 'WARN'
                    Write-Host \"    Connection dropped - reconnecting...\" -ForegroundColor Yellow
"""
if old_drop in ct:
    ct = replace_once(ct, old_drop, new_drop, 'win tunnel_drop')
    cp.write_text(ct, encoding='utf-8', newline='\n')
else:
    print('SKIP win tunnel_drop (already or mismatch)')
    # try softer
    if "Write-ConnectLog 'TUNNEL: connection dropped - auto reconnect' 'WARN'" in ct:
        ct = ct.replace(
            "Write-ConnectLog 'TUNNEL: connection dropped - auto reconnect' 'WARN'",
            "Write-ConnectLog (\"TUNNEL_DROP reason=auto_reconnect soft_fail=$($script:TunnelSoftFailCount) tunnel_sync_ok=$tunnelSyncOk project=$($go.Id) editor_opened=$editorOpened editor_seen=$($script:EditorSeenOpen) gen=$($script:RecoveryGeneration)\") 'WARN'",
            1)
        cp.write_text(ct, encoding='utf-8', newline='\n')
        print('OK win tunnel_drop soft')

# ---- connect-ui.sh ----
sp = Path('scripts/client/connect-ui.sh')
st = sp.read_text(encoding='utf-8')

sh_helpers = r'''
connect_session_id() {
    if [ -n "${CONNECT_SESSION_ID:-}" ] && [ "${#CONNECT_SESSION_ID}" -ge 4 ]; then
        printf '%s\n' "$CONNECT_SESSION_ID"
        return 0
    fi
    if [ -n "${CLAUDE_CONNECT_RUN_ID:-}" ] && [ "${#CLAUDE_CONNECT_RUN_ID}" -ge 8 ]; then
        CONNECT_SESSION_ID="$CLAUDE_CONNECT_RUN_ID"
    else
        CONNECT_SESSION_ID="$(python3 -c 'import uuid;print(uuid.uuid4().hex[:12])' 2>/dev/null || printf '%s%04d' "$(date +%s)" "$$")"
    fi
    export CONNECT_SESSION_ID
    export CLAUDE_CONNECT_RUN_ID="$CONNECT_SESSION_ID"
    printf '%s\n' "$CONNECT_SESSION_ID"
}

write_connect_session_index() {
    local phase="${1:-start}" project="${2:--}" ver="${3:-${CONNECT_VERSION:--}}"
    local dir="$HOME/.config/claude-connect/logs" idx sid ts host
    mkdir -p "$dir" 2>/dev/null || true
    idx="$dir/sessions.index"
    sid="$(connect_session_id)"
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"
    host="$(hostname 2>/dev/null || echo ?)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$sid" "$$" "${USER:-?}" "$host" "$ver" "$phase" "$project" >> "$idx" 2>/dev/null || true
}

'''

if 'connect_session_id()' not in st:
    st = replace_once(st, 'init_connect_log() {', sh_helpers + 'init_connect_log() {', 'sh helpers')

old_mac_sid = '''    CONNECT_LOG_PATH="$log_dir/connect-${day}.log"
    CONNECT_SESSION_ID="$(date +%s)-$$"
    wm="${CONNECT_LOG_PATH}.sync-offset"
'''
new_mac_sid = '''    CONNECT_LOG_PATH="$log_dir/connect-${day}.log"
    if [ -n "${CLAUDE_CONNECT_RUN_ID:-}" ] && [ "${#CLAUDE_CONNECT_RUN_ID}" -ge 8 ]; then
        CONNECT_SESSION_ID="$CLAUDE_CONNECT_RUN_ID"
    elif [ -n "${CONNECT_SESSION_ID:-}" ] && [ "${#CONNECT_SESSION_ID}" -ge 8 ]; then
        :
    else
        CONNECT_SESSION_ID="$(python3 -c 'import uuid;print(uuid.uuid4().hex[:12])' 2>/dev/null || printf '%s%04d' "$(date +%s)" "$$")"
    fi
    export CONNECT_SESSION_ID
    export CLAUDE_CONNECT_RUN_ID="$CONNECT_SESSION_ID"
    wm="${CONNECT_LOG_PATH}.sync-offset"
'''
if old_mac_sid in st:
    st = replace_once(st, old_mac_sid, new_mac_sid, 'sh reuse sid')

old_mac_start = '''    connect_log "======== session start v$version user=$USER pid=$$ session=$CONNECT_SESSION_ID ========"
    connect_log "log sink: local:$CONNECT_LOG_PATH watermark=$CONNECT_LOG_SYNC_OFF + server:~/.claude/logs/ (nightly purge)" 'INFO'
    connect_log "script_dir: $script_dir connect_version: $version" 'DEBUG'
}
'''
new_mac_start = '''    connect_log "======== session start v$version user=$USER pid=$$ session=$CONNECT_SESSION_ID ========"
    connect_log "log sink: local:$CONNECT_LOG_PATH watermark=$CONNECT_LOG_SYNC_OFF + server:~/.claude/logs/ (nightly purge)" 'INFO'
    connect_log "script_dir: $script_dir connect_version: $version" 'DEBUG'
    connect_log "SESSION_FILTER grep=[$CONNECT_SESSION_ID] tip=filter day log by bracketed session id"
    write_connect_session_index start - "$version"
}
'''
if old_mac_start in st:
    st = replace_once(st, old_mac_start, new_mac_start, 'sh filter')

# improve silent update path fallback for mac/connect-update.sh
old_ush = '''    update_sh="$script_dir/connect-update.sh"
    exit_code=1
'''
new_ush = '''    update_sh="$script_dir/connect-update.sh"
    if [ ! -f "$update_sh" ] && [ -f "$script_dir/mac/connect-update.sh" ]; then
        update_sh="$script_dir/mac/connect-update.sh"
    fi
    if [ ! -f "$update_sh" ] && [ -f "$(dirname "$script_dir")/mac/connect-update.sh" ]; then
        update_sh="$(dirname "$script_dir")/mac/connect-update.sh"
    fi
    exit_code=1
'''
if old_ush in st and 'mac/connect-update.sh' not in st[st.find('invoke_connect_silent_update_check'):st.find('invoke_connect_silent_update_check')+1200]:
    st = replace_once(st, old_ush, new_ush, 'sh update path')

sp.write_text(st, encoding='utf-8', newline='\n')

# ---- mac/connect.sh bootstrap RUN_ID ----
mp = Path('scripts/client/mac/connect.sh')
mt = mp.read_text(encoding='utf-8')
boot = '''set -uo pipefail

# Stable session id before update so BOOTSTRAP/UPDATE/session share one correlator.
if [ -z "${CLAUDE_CONNECT_RUN_ID:-}" ]; then
    CLAUDE_CONNECT_RUN_ID="$(python3 -c 'import uuid;print(uuid.uuid4().hex[:12])' 2>/dev/null || printf '%s%04d' "$(date +%s)" "$$")"
fi
export CLAUDE_CONNECT_RUN_ID
_day="$(date +%Y%m%d)"
_logdir="$HOME/.config/claude-connect/logs"
mkdir -p "$_logdir" 2>/dev/null || true
printf '[%s] [INFO] [%s] BOOTSTRAP: connect.sh start here=%s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$CLAUDE_CONNECT_RUN_ID" "$(cd "$(dirname "$0")" && pwd)" >> "$_logdir/connect-${_day}.log" 2>/dev/null || true

_update_script=
'''
# careful - only insert if not present
if 'BOOTSTRAP: connect.sh start' not in mt:
    old_top = '''set -uo pipefail

_update_script="$(cd "$(dirname "$0")" && pwd)/connect-update.sh"
'''
    new_top = '''set -uo pipefail

# Stable session id before update so BOOTSTRAP/UPDATE/session share one correlator.
if [ -z "${CLAUDE_CONNECT_RUN_ID:-}" ]; then
    CLAUDE_CONNECT_RUN_ID="$(python3 -c 'import uuid;print(uuid.uuid4().hex[:12])' 2>/dev/null || printf '%s%04d' "$(date +%s)" "$$")"
fi
export CLAUDE_CONNECT_RUN_ID
_day="$(date +%Y%m%d)"
_logdir="$HOME/.config/claude-connect/logs"
mkdir -p "$_logdir" 2>/dev/null || true
printf '[%s] [INFO] [%s] BOOTSTRAP: connect.sh start here=%s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$CLAUDE_CONNECT_RUN_ID" "$(cd "$(dirname "$0")" && pwd)" >> "$_logdir/connect-${_day}.log" 2>/dev/null || true

_update_script="$(cd "$(dirname "$0")" && pwd)/connect-update.sh"
'''
    if old_top in mt:
        mt = replace_once(mt, old_top, new_top, 'mac bootstrap')
    else:
        print('MISS mac top exact')

# Mac TUNNEL_DROP on auto - find connection dropped recovering
if "connect_log 'TUNNEL: recovering session" in mt and 'TUNNEL_DROP reason=auto_reconnect' not in mt:
    # enrich auto reconnect printf path - look for Connection dropped - recovering
    needle = "printf '    Connection dropped - recovering...\\n'"
    if needle in mt:
        mt = mt.replace(needle,
            "printf '    Connection dropped - recovering...\\n'\n"
            "                if declare -F connect_log >/dev/null 2>&1; then\n"
            "                    connect_log \"TUNNEL_DROP reason=auto_reconnect project=${go_id:-?} editor_opened=${_editor_opened:-0} editor_seen=${_editor_seen_open:-0} gen=${RECOVERY_GENERATION:-0} soft_fail=${_TUNNEL_SOFT_FAIL_COUNT:-?}\" 'WARN'\n"
            "                fi",
            1)
        print('OK mac tunnel_drop')

mp.write_text(mt, encoding='utf-8', newline='\n')

# ---- connect-update.ps1 ensure sid ----
up = Path('scripts/client/windows/connect-update.ps1')
ut = up.read_text(encoding='utf-8')
if 'if (-not $env:CLAUDE_CONNECT_RUN_ID' not in ut[:800]:
    old = '''Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if (-not $ScriptDir) {
'''
    new = '''Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if (-not $env:CLAUDE_CONNECT_RUN_ID -or $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -lt 8) {
    $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
}

if (-not $ScriptDir) {
'''
    if old in ut:
        ut = replace_once(ut, old, new, 'win update sid')
        up.write_text(ut, encoding='utf-8', newline='\n')

# ---- mac connect-update ensure sid ----
mu = Path('scripts/client/mac/connect-update.sh')
mut = mu.read_text(encoding='utf-8')
if 'CLAUDE_CONNECT_RUN_ID' in mut and 'uuid4' not in mut[:40]:
    # add near top after set
    if 'if [ -z "${CLAUDE_CONNECT_RUN_ID:-}" ]' not in mut:
        old = 'set -uo pipefail\n'
        new = '''set -uo pipefail
if [ -z "${CLAUDE_CONNECT_RUN_ID:-}" ]; then
    CLAUDE_CONNECT_RUN_ID="$(python3 -c 'import uuid;print(uuid.uuid4().hex[:12])' 2>/dev/null || printf '%s%04d' "$(date +%s)" "$$")"
    export CLAUDE_CONNECT_RUN_ID
fi
'''
        if mut.startswith('#!/bin/bash\n# connect-update'):
            # insert after set -uo
            if 'set -uo pipefail\n' in mut:
                mut = replace_once(mut, 'set -uo pipefail\n', new, 'mac update sid')
                mu.write_text(mut, encoding='utf-8', newline='\n')

print('DONE')
