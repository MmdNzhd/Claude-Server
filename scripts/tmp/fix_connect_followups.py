from pathlib import Path
import re

# --- 1) connect.ps1: path warn + always elevate + version ---
ps1 = Path('scripts/client/windows/connect.ps1')
t = ps1.read_text(encoding='utf-8')

t = t.replace("$script:ConnectVersion = '20260720.7'", "$script:ConnectVersion = '20260720.8'")

old_sec = """# SECURITY: do NOT always elevate the whole connect session (UAC + attack surface).
# sshd / firewall / administrators_authorized_keys are fixed on demand via
# Ensure-LaptopSshReady -> Invoke-LaptopAdminOps (-AdminFix child, UAC once).
# Normal session stays unelevated; secrets (keys, logs) stay out of an always-admin process.
"""
new_sec = """# Always elevate the main connect UI (admin sshd / administrators_authorized_keys / firewall).
# -AdminFix child still used for targeted pending fixes; unelevated launch re-execs via UAC once.
"""
if old_sec not in t:
    raise SystemExit('elevate comment block missing')
t = t.replace(old_sec, new_sec, 1)

# Insert always-elevate after RunAdminFix assignment if not already present
marker = "$script:RunAdminFix = [bool]$AdminFix"
elevate_block = """$script:RunAdminFix = [bool]$AdminFix

if (-not $script:RunAdminFix) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        $elevArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) + $args
        try {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevArgs -PassThru -Wait
            exit $(if ($null -ne $p -and $null -ne $p.ExitCode) { $p.ExitCode } else { 1 })
        } catch {
            Write-Host '[X] Administrator elevation required (UAC cancelled or failed).' -ForegroundColor Red
            try {
                $d = Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'
                New-Item -ItemType Directory -Force -Path $d | Out-Null
                $f = Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID } else { '-' }
                [IO.File]::AppendAllText($f, "[$ts] [ERROR] [$sid] FAIL ADMIN_ELEVATE: UAC cancelled or failed`n", [Text.UTF8Encoding]::new($false))
            } catch {}
            exit 1
        }
    }
}
"""
if 'FAIL ADMIN_ELEVATE' not in t:
    if marker not in t:
        raise SystemExit('RunAdminFix marker missing')
    t = t.replace(marker, elevate_block, 1)

old_path = """                if ($mountOut -match 'No such file|not found|cannot find') {
                    Warn "Path not found on laptop. Use 'e edit' to correct the project path."
                }"""
new_path = """                if ($mountOut -match 'No such file|cannot find|path does not exist' -and $mountOut -notmatch 'command not found|_emit_git') {
                    Warn "Path not found on laptop. Use 'e edit' to correct the project path."
                } elseif ($mountOut -match 'command not found|_emit_git_hide_warn') {
                    Warn "Server mount script broken/outdated - reconnect to re-push claude-mount (or re-run publish deploy)."
                }"""
if old_path not in t:
    raise SystemExit('path warn block missing')
t = t.replace(old_path, new_path, 1)

ps1.write_text(t, encoding='utf-8', newline='\n')
print('OK connect.ps1')

# --- 2) git-mode Resolve-ServerScriptDir ---
gm = Path('scripts/client/git-mode.ps1')
g = gm.read_text(encoding='utf-8')
old_resolve = """function Resolve-ServerScriptDir {
    param([Parameter(Mandatory)][string]$ConnectScriptDir)
    try {
        $bundleServer = [System.IO.Path]::Combine($ConnectScriptDir, 'server')
        if (Test-Path ([System.IO.Path]::Combine($bundleServer, 'laptop-exec.sh'))) { return $bundleServer }
    } catch { }
    foreach ($rel in @('..\\server', '..\\..\\server', '..\\..\\..\\server')) {
        try {
            $d = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            if (Test-Path ([System.IO.Path]::Combine($d, 'claude-mount.sh'))) { return $d }
        } catch { }
    }
    try {
        $d = $ConnectScriptDir
        for ($i = 0; $i -lt 8; $i++) {
            $repoServer = [System.IO.Path]::Combine($d, 'scripts', 'server')
            if (Test-Path ([System.IO.Path]::Combine($repoServer, 'claude-mount.sh'))) { return $repoServer }
            $adjServer = [System.IO.Path]::Combine($d, 'server')
            if (Test-Path ([System.IO.Path]::Combine($adjServer, 'claude-mount.sh'))) { return $adjServer }
            $parent = Split-Path $d -Parent
            if (-not $parent -or $parent -eq $d) { break }
            $d = $parent
        }
    } catch { }
    return $null
}"""
new_resolve = """function Resolve-ServerScriptDir {
    param([Parameter(Mandatory)][string]$ConnectScriptDir)
    # Prefer package mac/ (published fresh claude-mount) over nested windows/server stale copies.
    foreach ($rel in @('..\\mac', 'mac', '..\\..\\mac')) {
        try {
            $d = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            if (Test-Path ([System.IO.Path]::Combine($d, 'claude-mount.sh'))) { return $d }
        } catch { }
    }
    try {
        $d = $ConnectScriptDir
        for ($i = 0; $i -lt 8; $i++) {
            $repoServer = [System.IO.Path]::Combine($d, 'scripts', 'server')
            if (Test-Path ([System.IO.Path]::Combine($repoServer, 'claude-mount.sh'))) { return $repoServer }
            $parent = Split-Path $d -Parent
            if (-not $parent -or $parent -eq $d) { break }
            $d = $parent
        }
    } catch { }
    foreach ($rel in @('server', '..\\server', '..\\..\\server')) {
        try {
            $d = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            if (Test-Path ([System.IO.Path]::Combine($d, 'claude-mount.sh'))) { return $d }
        } catch { }
    }
    return $null
}"""
# normalize line endings for match
g_norm = g.replace('\r\n', '\n')
if old_resolve not in g_norm:
    # try flexible
    m = re.search(r'function Resolve-ServerScriptDir \{.*?\n\}', g_norm, re.S)
    if not m:
        raise SystemExit('Resolve-ServerScriptDir not found')
    g_norm = g_norm[:m.start()] + new_resolve + g_norm[m.end():]
    print('OK resolve via regex')
else:
    g_norm = g_norm.replace(old_resolve, new_resolve, 1)
    print('OK resolve exact')
gm.write_text(g_norm, encoding='utf-8', newline='\n')

# --- 3) version txt ---
for vp in [Path('scripts/client/windows/connect-version.txt'), Path('scripts/client/mac/connect-version.txt')]:
    vp.write_text('20260720.8\n', encoding='utf-8', newline='\n')
    print('OK', vp)

# mac connect version string if present
mac = Path('scripts/client/mac/connect.sh')
mt = mac.read_text(encoding='utf-8')
mt2 = mt.replace("CONNECT_VERSION='20260720.7'", "CONNECT_VERSION='20260720.8'")
if mt2 != mt:
    mac.write_text(mt2, encoding='utf-8', newline='\n')
    print('OK mac version')

# harden _emit to strip CR
cm = Path('scripts/server/claude-mount.sh')
ct = cm.read_text(encoding='utf-8')
old_emit = '''_emit_git_hide_warn() {
    local ps_out="$1"
    local hide_status
    hide_status=$(printf '%s\\n' "$ps_out" | grep -o 'GIT_HIDE:.*' | tail -1 || true)'''
new_emit = '''_emit_git_hide_warn() {
    local ps_out="$1"
    ps_out="${ps_out//$'\\r'/}"
    local hide_status
    hide_status=$(printf '%s\\n' "$ps_out" | grep -o 'GIT_HIDE:.*' | tail -1 || true)'''
if old_emit in ct:
    ct = ct.replace(old_emit, new_emit, 1)
    cm.write_text(ct, encoding='utf-8', newline='\n')
    print('OK emit strip cr')
else:
    print('WARN emit block not exact; skip strip')

print('DONE')
