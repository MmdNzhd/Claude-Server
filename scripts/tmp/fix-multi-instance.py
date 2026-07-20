from pathlib import Path

root = Path('.')  # run from repo root via laptop-exec

# ---- connect-ui.ps1 ----
p = root / 'scripts/client/connect-ui.ps1'
c = p.read_text(encoding='utf-8')
old = '''function Enter-ConnectSingleInstance {
    # One connect UI per Windows user. Prevents Sepidz+Smart dual tunnels fighting.
    param([string]$Name = '')
    if (-not $Name) { $Name = ("Global\\ClaudeConnect-{0}" -f $env:USERNAME) }
    try {
        $created = $false
        $m = New-Object System.Threading.Mutex($false, $Name, [ref]$created)
        $script:ConnectInstanceMutex = $m
        if (-not $m.WaitOne(0)) {
            try { $m.Dispose() } catch { }
            $script:ConnectInstanceMutex = $null
            Write-Host ''
            Write-Host '  [X] Another Claude Connect is already running on this PC.' -ForegroundColor Red
            Write-Host '      Close it (Q) first. Running two (Smart+Sepidz) breaks tunnel/logs.' -ForegroundColor Yellow
            Write-Host ''
            return $false
        }
        Write-ConnectLog ("SINGLE_INSTANCE: acquired mutex={0} pid={1}" -f $Name, $PID) 'INFO'
        return $true
    } catch {
        # If mutex APIs fail, do not block connect.
        Write-ConnectLog ("SINGLE_INSTANCE: mutex error (continue): {0}" -f $_.Exception.Message) 'WARN'
        return $true
    }
}

function Exit-ConnectSingleInstance {
    try {
        if ($script:ConnectInstanceMutex) {
            try { $script:ConnectInstanceMutex.ReleaseMutex() } catch { }
            try { $script:ConnectInstanceMutex.Dispose() } catch { }
            $script:ConnectInstanceMutex = $null
        }
    } catch { }
}'''
new = '''function Enter-ConnectSingleInstance {
    # Unlimited concurrent connect UIs. Tunnel slots (Acquire-TunnelPort 0..9) + session IDs isolate tunnels/logs.
    param([string]$Name = '')
    $script:ConnectInstanceMutex = $null
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("MULTI_INSTANCE: allowed pid={0} (no global mutex)" -f $PID) 'INFO'
    }
    return $true
}

function Exit-ConnectSingleInstance {
    # No-op: multi-instance mode does not hold a process-wide mutex.
    $script:ConnectInstanceMutex = $null
}'''
if old not in c:
    raise SystemExit('connect-ui.ps1: old block not found')
p.write_text(c.replace(old, new, 1), encoding='utf-8', newline='\n')
print('OK connect-ui.ps1')

# ---- connect-ui.sh ----
p = root / 'scripts/client/connect-ui.sh'
c = p.read_text(encoding='utf-8')
old = '''enter_connect_single_instance() {
    # One connect per user via flock on lock file.
    local lockdir="${HOME}/.config/claude-connect"
    local lockfile="${lockdir}/connect.lock"
    mkdir -p "$lockdir" 2>/dev/null || true
    exec 9>"$lockfile" || return 0
    if ! flock -n 9; then
        printf '\\n  [X] Another Claude Connect is already running on this Mac.\\n' >&2
        printf '      Close it (q) first. Two sessions break tunnel/logs.\\n\\n' >&2
        return 1
    fi
    CONNECT_LOCK_HELD=1
    connect_log "SINGLE_INSTANCE: acquired flock pid=$$" 'INFO'
    return 0
}

exit_connect_single_instance() {
    if [ "${CONNECT_LOCK_HELD:-0}" = 1 ]; then
        flock -u 9 2>/dev/null || true
        CONNECT_LOCK_HELD=0
    fi
}'''
new = '''enter_connect_single_instance() {
    # Unlimited concurrent connect UIs. Tunnel slots + session IDs isolate tunnels/logs.
    CONNECT_LOCK_HELD=0
    connect_log "MULTI_INSTANCE: allowed pid=$$ (no flock)" 'INFO'
    return 0
}

exit_connect_single_instance() {
    # No-op: multi-instance mode does not hold a process-wide flock.
    CONNECT_LOCK_HELD=0
}'''
if old not in c:
    raise SystemExit('connect-ui.sh: old block not found')
p.write_text(c.replace(old, new, 1), encoding='utf-8', newline='\n')
print('OK connect-ui.sh')

# ---- connect-update.ps1: move Ensure-ConnectRunId before first call ----
p = root / 'scripts/client/windows/connect-update.ps1'
c = p.read_text(encoding='utf-8')
# Remove premature call
bad = '''try { $ScriptDir = [IO.Path]::GetFullPath($ScriptDir) } catch {}

$null = Ensure-ConnectRunId

$RemoteBundle'''
good = '''try { $ScriptDir = [IO.Path]::GetFullPath($ScriptDir) } catch {}

$RemoteBundle'''
if bad not in c:
    raise SystemExit('connect-update.ps1: premature call block not found')
c = c.replace(bad, good, 1)
# Move function to right after SshCommonOpts block start area - insert before first use via placing after Quiet setup
# Ensure function exists before Write-UpdateFileLog uses it - it's already defined later.
# Add early definition after script:Quiet
anchor = '''$script:Quiet = [bool]$Quiet

if (-not $ScriptDir) {'''
fn = '''$script:Quiet = [bool]$Quiet

function Ensure-ConnectRunId {
    if ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
        $env:CLAUDE_CONNECT_RUN_ID = $env:CLAUDE_CONNECT_RUN_ID.Trim()
        return $env:CLAUDE_CONNECT_RUN_ID
    }
    $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
    return $env:CLAUDE_CONNECT_RUN_ID
}

if (-not $ScriptDir) {'''
if anchor not in c:
    raise SystemExit('connect-update.ps1: Quiet anchor not found')
c = c.replace(anchor, fn, 1)
# Remove duplicate later function definition
dup = '''

function Ensure-ConnectRunId {
    if ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
        $env:CLAUDE_CONNECT_RUN_ID = $env:CLAUDE_CONNECT_RUN_ID.Trim()
        return $env:CLAUDE_CONNECT_RUN_ID
    }
    $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
    return $env:CLAUDE_CONNECT_RUN_ID
}

function Write-UpdateMsg {'''
if dup not in c:
    raise SystemExit('connect-update.ps1: duplicate Ensure-ConnectRunId not found')
c = c.replace(dup, '\n\nfunction Write-UpdateMsg {', 1)
# Call once after function exists (after ScriptDir normalize) for early env seed
seed = '''try { $ScriptDir = [IO.Path]::GetFullPath($ScriptDir) } catch {}

$RemoteBundle'''
seed2 = '''try { $ScriptDir = [IO.Path]::GetFullPath($ScriptDir) } catch {}

$null = Ensure-ConnectRunId

$RemoteBundle'''
if seed not in c:
    raise SystemExit('connect-update.ps1: seed insert point missing')
c = c.replace(seed, seed2, 1)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect-update.ps1')

# ---- designer connect.ps1: remove mutex fallback ----
p = root / 'scripts/client/users/designer/connect.ps1'
c = p.read_text(encoding='utf-8')
old = '''# Share main connect mutex (inline fallback when connect-ui.ps1 not in package).
if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    if (-not (Enter-ConnectSingleInstance)) {
        if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) { Wait-ConnectExit -Reason 'single_instance' -Code 2 }
        else { exit 2 }
    }
} else {
    $script:ConnectInstanceMutex = $null
    try {
        $created = $false
        $m = New-Object System.Threading.Mutex($false, ("Global\\ClaudeConnect-{0}" -f $env:USERNAME), [ref]$created)
        $script:ConnectInstanceMutex = $m
        if (-not $m.WaitOne(0)) {
            try { $m.Dispose() } catch { }
            $script:ConnectInstanceMutex = $null
            Write-Host ''
            Write-Host '  [X] Another Claude Connect is already running on this PC.' -ForegroundColor Red
            Write-Host '      Close it (Q) first. Designer + main connect cannot share the tunnel.' -ForegroundColor Yellow
            Write-Host ''
            exit 2
        }
    } catch { }
}

'''
new = '''# Multi-instance: Enter-ConnectSingleInstance is a no-op (unlimited concurrent UIs).
if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    $null = Enter-ConnectSingleInstance
}

'''
if old not in c:
    raise SystemExit('designer connect.ps1: mutex block not found')
p.write_text(c.replace(old, new, 1), encoding='utf-8', newline='\n')
print('OK designer connect.ps1')

# ---- designer connect.sh ----
p = root / 'scripts/client/users/designer/connect.sh'
c = p.read_text(encoding='utf-8')
old = '''# Share main connect flock so designer cannot fight Smart/Sepidz tunnels.
_designer_lockdir="${HOME}/.config/claude-connect"
_designer_lockfile="${_designer_lockdir}/connect.lock"
mkdir -p "$_designer_lockdir" 2>/dev/null || true
exec 9>"$_designer_lockfile" || true
if ! flock -n 9; then
    printf '\\n  [X] Another Claude Connect is already running on this Mac.\\n' >&2
    printf '      Close it (q) first. Designer + main connect cannot share the tunnel.\\n\\n' >&2
    exit 1
fi

'''
new = '''# Multi-instance: no global flock (unlimited concurrent UIs; tunnel slots isolate ports).

'''
if old not in c:
    raise SystemExit('designer connect.sh: flock block not found')
p.write_text(c.replace(old, new, 1), encoding='utf-8', newline='\n')
print('OK designer connect.sh')

# ---- connect-design.ps1 ----
p = root / 'scripts/client/windows/connect-design.ps1'
c = p.read_text(encoding='utf-8')
old = '''# Shared single-instance lock with main connect (same Global\\ClaudeConnect-{user}).
$script:ConnectScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$_connectUi = Join-Path $script:ConnectScriptDir 'connect-ui.ps1'
if (-not (Test-Path $_connectUi)) {
    $_connectUi = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'connect-ui.ps1'
}
if (-not (Test-Path $_connectUi)) {
    $_connectUi = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'connect-ui.ps1'
}
if (Test-Path $_connectUi) {
    . $_connectUi
    if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
        if (-not (Enter-ConnectSingleInstance)) {
            if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) { Wait-ConnectExit -Reason 'single_instance' -Code 2 }
            else { try { Read-Host '    Press Enter to close' | Out-Null } catch { }; exit 2 }
        }
    }
}

'''
new = '''# Multi-instance: load connect-ui helpers; single-instance lock is a no-op.
$script:ConnectScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$_connectUi = Join-Path $script:ConnectScriptDir 'connect-ui.ps1'
if (-not (Test-Path $_connectUi)) {
    $_connectUi = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'connect-ui.ps1'
}
if (-not (Test-Path $_connectUi)) {
    $_connectUi = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'connect-ui.ps1'
}
if (Test-Path $_connectUi) {
    . $_connectUi
    if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
        $null = Enter-ConnectSingleInstance
    }
}

'''
if old not in c:
    raise SystemExit('connect-design.ps1: block not found')
p.write_text(c.replace(old, new, 1), encoding='utf-8', newline='\n')
print('OK connect-design.ps1')

# bump version
vp = root / 'scripts/client/windows/connect-version.txt'
# find all connect-version.txt
for vp in root.glob('scripts/client/**/connect-version.txt'):
    vp.write_text('20260720.2\n', encoding='utf-8')
    print('version', vp)
# also top-level if any
for vp in [root / 'scripts/client/connect-version.txt', root / 'scripts/client/mac/connect-version.txt']:
    if vp.exists():
        vp.write_text('20260720.2\n', encoding='utf-8')
        print('version', vp)

print('DONE')
