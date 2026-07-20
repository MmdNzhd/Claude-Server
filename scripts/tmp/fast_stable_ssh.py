# -*- coding: utf-8 -*-
"""Stable speedups: SSH mux (like Mac) + batch conf read/push. No update/retry changes. No Smart."""
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')

# ---------- connect.ps1: mux on Invoke-SshXCore + cleanup helper ----------
cp = root / 'scripts/client/windows/connect.ps1'
ct = cp.read_text(encoding='utf-8')

old_core = '''function Invoke-SshXCore {
    param([Parameter(Mandatory)][string]$RemoteCmd)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lines = @(& ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 `
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 $Alias $RemoteCmd 2>&1)
    $sw.Stop()
    if ($null -eq $lines) { $lines = @() }
    return [PSCustomObject]@{
        Exit = $LASTEXITCODE
        Ms   = [int]$sw.ElapsedMilliseconds
        Out  = ($lines -join "`n")
        Lines = $lines
    }
}'''

new_core = '''function Get-ConnectSshMuxPath {
    # Windows OpenSSH ControlMaster requires a named-pipe ControlPath (same idea as Mac ControlPersist).
    # Per-alias pipe so Smart/Sepidz sessions never share a mux socket.
    if (-not $script:ConnectSshMuxPath) {
        $safe = if ($Alias) { ($Alias -replace '[^A-Za-z0-9_-]', '_') } else { 'claude' }
        $script:ConnectSshMuxPath = "\\\\.\\pipe\\claude-connect-$safe-%C"
    }
    return $script:ConnectSshMuxPath
}

function Stop-ConnectSshMux {
    # Best-effort; never throws. Keeps stability if mux already gone.
    try {
        if (-not $Alias) { return }
        $path = Get-ConnectSshMuxPath
        & ssh -O exit -o ControlPath=$path $Alias 2>$null | Out-Null
    } catch { }
    $script:ConnectSshMuxPath = $null
}

function Invoke-SshXCore {
    param([Parameter(Mandatory)][string]$RemoteCmd)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Stability: keep ClearAllForwardings so interactive SshX never steals the reverse tunnel.
    # Speed: ControlMaster=auto reuses one TCP+auth to the server (Mac parity). Update/sync paths
    # still use ControlMaster=no and are unaffected.
    $mux = Get-ConnectSshMuxPath
    $lines = @(& ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 `
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 `
        -o ControlMaster=auto -o ControlPath=$mux -o ControlPersist=120 `
        $Alias $RemoteCmd 2>&1)
    $sw.Stop()
    if ($null -eq $lines) { $lines = @() }
    return [PSCustomObject]@{
        Exit = $LASTEXITCODE
        Ms   = [int]$sw.ElapsedMilliseconds
        Out  = ($lines -join "`n")
        Lines = $lines
    }
}'''

if old_core not in ct:
    raise SystemExit('Invoke-SshXCore block not found')
ct = ct.replace(old_core, new_core, 1)

# Wire mux cleanup into Close-ConnectLog callers? Better: patch connect-ui Close-ConnectLog
# Also call Stop-ConnectSshMux near end of connect.ps1 exit paths - find Close-ConnectLog in connect-ui

cp.write_text(ct, encoding='utf-8', newline='\n')
print('patched connect.ps1 mux')

# ---------- connect-ui.ps1: exit mux on close ----------
ui = root / 'scripts/client/connect-ui.ps1'
ut = ui.read_text(encoding='utf-8')
old_close_tail = '''    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }
    # Keep durable local day log so offline / failed-SSH sessions remain auditable.
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
    Exit-ConnectSingleInstance
}'''

new_close_tail = '''    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }
    # Keep durable local day log so offline / failed-SSH sessions remain auditable.
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
    if (Get-Command Stop-ConnectSshMux -ErrorAction SilentlyContinue) { Stop-ConnectSshMux }
    Exit-ConnectSingleInstance
}'''

# Close-ConnectLog has two paths - early return and main. Patch both Exit-ConnectSingleInstance areas.
count = ut.count('Exit-ConnectSingleInstance')
if count < 1:
    raise SystemExit('Exit-ConnectSingleInstance missing')
# Insert Stop-ConnectSshMux before every Exit-ConnectSingleInstance inside Close-ConnectLog only
# Safer: replace the function carefully
m = re.search(r'(?s)function Close-ConnectLog \{.*?\n\}', ut)
if not m:
    raise SystemExit('Close-ConnectLog not found')
close_fn = m.group(0)
if 'Stop-ConnectSshMux' not in close_fn:
    close_fn2 = close_fn.replace(
        'Exit-ConnectSingleInstance',
        'if (Get-Command Stop-ConnectSshMux -ErrorAction SilentlyContinue) { Stop-ConnectSshMux }\n    Exit-ConnectSingleInstance'
    )
    # Only first occurrence in early path and last - the replace_all is OK (both exit paths should stop mux)
    ut = ut[:m.start()] + close_fn2 + ut[m.end():]
    ui.write_text(ut, encoding='utf-8', newline='\n')
    print('patched Close-ConnectLog mux exit')
else:
    print('Close-ConnectLog already has mux exit')

# ---------- git-mode.ps1: batch Warn-Foreign + Push ----------
gm = root / 'scripts/client/git-mode.ps1'
gt = gm.read_text(encoding='utf-8')

old_warn = '''function Warn-ForeignServerSession {
    # Return $true to continue, $false when user aborts a likely wrong-account takeover.
    # Self-heal: stale conf + no listening reverse tunnel -> clear and continue.
    $existingLu = ((SshX "grep -E '^LAPTOP_USER=' ~/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-") -join '').Trim()
    $existingOs = ((SshX "grep -E '^LAPTOP_OS=' ~/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-") -join '').Trim()
    $existingPort = ((SshX "grep -E '^TUNNEL_PORT=' ~/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-") -join '').Trim()
    if (-not $existingLu) { return $true }
    $mine = if ($script:LaptopUser) { $script:LaptopUser } elseif ($env:USERNAME) { $env:USERNAME } else { $env:USER }
    if ($existingLu -eq $mine) { return $true }

    $portDigits = -join (($existingPort.ToCharArray() | Where-Object { $_ -match '[0-9]' }))
    $live = 0
    if ($portDigits) {
        $liveCmd = "ss -ltn 2>/dev/null | grep -cE ':{0}[[:space:]]' || true" -f $portDigits
        $liveRaw = ((SshX $liveCmd) -join '').Trim()
        if ($liveRaw -match '^[0-9]+$') { $live = [int]$liveRaw }
    }
    if (-not $portDigits -or $live -eq 0) {
        Warn ("Cleared stale session from laptop '{0}' (no active tunnel)." -f $existingLu)
        SshX 'rm -f ~/.claude-connect.conf' 2>$null | Out-Null
        return $true
    }'''

new_warn = '''function Warn-ForeignServerSession {
    # Return $true to continue, $false when user aborts a likely wrong-account takeover.
    # Self-heal: stale conf + no listening reverse tunnel -> clear and continue.
    # Speed (stable): one SSH reads conf (+ live port check when foreign), instead of 3-4 greps.
    $probe = @((SshX @'
set +e
CONF="$HOME/.claude-connect.conf"
LU=""; OS=""; PORT=""
if [ -f "$CONF" ]; then
  LU=$(grep -E '^LAPTOP_USER=' "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
  OS=$(grep -E '^LAPTOP_OS=' "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
  PORT=$(grep -E '^TUNNEL_PORT=' "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
printf 'LU=%s\nOS=%s\nPORT=%s\n' "$LU" "$OS" "$PORT"
'@) ) -join "`n")
    $existingLu = ''; $existingOs = ''; $existingPort = ''
    foreach ($ln in ($probe -split "`r?`n")) {
        if ($ln -match '^LU=(.*)$') { $existingLu = $Matches[1].Trim() }
        elseif ($ln -match '^OS=(.*)$') { $existingOs = $Matches[1].Trim() }
        elseif ($ln -match '^PORT=(.*)$') { $existingPort = $Matches[1].Trim() }
    }
    if (-not $existingLu) { return $true }
    $mine = if ($script:LaptopUser) { $script:LaptopUser } elseif ($env:USERNAME) { $env:USERNAME } else { $env:USER }
    if ($existingLu -eq $mine) { return $true }

    $portDigits = -join (($existingPort.ToCharArray() | Where-Object { $_ -match '[0-9]' }))
    $live = 0
    if ($portDigits) {
        $liveCmd = "ss -ltn 2>/dev/null | grep -cE ':{0}[[:space:]]' || true" -f $portDigits
        $liveRaw = ((SshX $liveCmd) -join '').Trim()
        if ($liveRaw -match '^[0-9]+$') { $live = [int]$liveRaw }
    }
    if (-not $portDigits -or $live -eq 0) {
        Warn ("Cleared stale session from laptop '{0}' (no active tunnel)." -f $existingLu)
        SshX 'rm -f ~/.claude-connect.conf' 2>$null | Out-Null
        return $true
    }'''

if old_warn not in gt:
    raise SystemExit('Warn-ForeignServerSession head not found')
gt = gt.replace(old_warn, new_warn, 1)

old_push = '''function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Edge: tunnel-ensure / SSH-setup used to push ACTIVE_MOUNT='' and wipe the
    # server conf mid-session — automount skipped — Cursor opened empty mounts.
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

# The dash character in comment might be special - read exact from file
# Find function Push-ServerConnectConf and replace until next function
m = re.search(r'(?s)function Push-ServerConnectConf \{.*?\n\}\n\nfunction Read-RetryQuitKey', gt)
if not m:
    m = re.search(r'(?s)function Push-ServerConnectConf \{.*?\n\}\r?\n\r?\nfunction Read-RetryQuitKey', gt)
if not m:
    raise SystemExit('Push-ServerConnectConf block not found')

new_push = '''function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Edge: tunnel-ensure / SSH-setup used to push ACTIVE_MOUNT='' and wipe the
    # server conf mid-session - automount skipped - Cursor opened empty mounts.
    # Preserve existing server ACTIVE_MOUNT unless caller clears or sets explicitly.
    # Speed (stable): preserve+write+self-heal in ONE SSH (same semantics as before).
    $preferAm = ''
    if (-not $ClearActiveMount) {
        if (-not [string]::IsNullOrWhiteSpace($ActiveMount)) {
            $preferAm = [string]$ActiveMount
        } elseif ($script:ActiveProjectId) {
            $preferAm = [string]$script:ActiveProjectId
        }
    }
    $lu = ($LaptopUser -replace "'", "'\\''")
    $modeEsc = ($mode -replace "'", "'\\''")
    $preferEsc = ($preferAm -replace "'", "'\\''")
    $clearFlag = if ($ClearActiveMount) { '1' } else { '0' }
    $portEsc = "$Port" -replace "'", "'\\''"
    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode prefer_mount=$preferAm clear=$ClearActiveMount" 'DEBUG'
    $remote = @"
set +e
CLEAR='$clearFlag'
PREFER='$preferEsc'
AM=''
if [ "\$CLEAR" = '1' ]; then
  AM=''
elif [ -n "\$PREFER" ]; then
  AM="\$PREFER"
else
  AM=\$(grep -E '^ACTIVE_MOUNT=' "\$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
mkdir -p "\$HOME/.local/bin"
printf 'LAPTOP_USER=%s\\nTUNNEL_PORT=%s\\nGIT_MODE=%s\\nLAPTOP_OS=windows\\nACTIVE_MOUNT=%s\\n' '$lu' '$portEsc' '$modeEsc' "\$AM" > "\$HOME/.claude-connect.conf"
chmod 600 "\$HOME/.claude-connect.conf" 2>/dev/null || true
/usr/local/bin/claude-self-heal --quiet 2>/dev/null || "\$HOME/.local/bin/claude-self-heal" --quiet 2>/dev/null || true
true
"@
    SshX $remote 2>$null | Out-Null
}

function Read-RetryQuitKey'''

# Careful: the @" "@ string in the Python triple-quoted string - the remote bash needs
# proper escaping when embedded in PowerShell. Using a simpler approach without nested here-strings.

new_push = r'''function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Preserve existing server ACTIVE_MOUNT unless caller clears or sets explicitly.
    # Speed (stable): preserve+write+self-heal in ONE SSH (same semantics as before).
    $preferAm = ''
    if (-not $ClearActiveMount) {
        if (-not [string]::IsNullOrWhiteSpace($ActiveMount)) {
            $preferAm = [string]$ActiveMount
        } elseif ($script:ActiveProjectId) {
            $preferAm = [string]$script:ActiveProjectId
        }
    }
    $lu = ($LaptopUser -replace "'", "'\''")
    $modeEsc = ($mode -replace "'", "'\''")
    $preferEsc = ($preferAm -replace "'", "'\''")
    $portEsc = ("$Port" -replace "'", "'\''")
    $clearFlag = if ($ClearActiveMount) { '1' } else { '0' }
    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode prefer_mount=$preferAm clear=$ClearActiveMount" 'DEBUG'
    $remote = @(
        'set +e'
        "CLEAR='$clearFlag'"
        "PREFER='$preferEsc'"
        "LU='$lu'"
        "PORT='$portEsc'"
        "MODE='$modeEsc'"
        'AM=""'
        'if [ "$CLEAR" = "1" ]; then AM=""'
        'elif [ -n "$PREFER" ]; then AM="$PREFER"'
        'else AM=$(grep -E "^ACTIVE_MOUNT=" "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)'
        'fi'
        'mkdir -p "$HOME/.local/bin"'
        'printf "LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n" "$LU" "$PORT" "$MODE" "$AM" > "$HOME/.claude-connect.conf"'
        'chmod 600 "$HOME/.claude-connect.conf" 2>/dev/null || true'
        '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || "$HOME/.local/bin/claude-self-heal" --quiet 2>/dev/null || true'
        'true'
    ) -join '; '
    SshX $remote 2>$null | Out-Null
}

function Read-RetryQuitKey'''

gt = gt[:m.start()] + new_push + gt[m.end():]
# Fix: m.end() already includes through Read-RetryQuitKey start - new_push ends with Read-RetryQuitKey
# Check we didn't duplicate
if gt.count('function Read-RetryQuitKey') != 1:
    # restore issue - the match consumed 'function Read-RetryQuitKey' so new_push should end with it and rest follows
    pass
# Actually m was `...}\n\nfunction Read-RetryQuitKey` so m.end() is after Read-RetryQuitKey
# and new_push ends with `function Read-RetryQuitKey` - then gt[m.end():] continues with ` {` of Read-RetryQuitKey
# So we get `function Read-RetryQuitKey {` - GOOD if m ended right after the name.

# Verify
if gt.count('function Push-ServerConnectConf') != 1:
    raise SystemExit('Push count wrong')
if gt.count('function Read-RetryQuitKey') != 1:
    raise SystemExit(f'Read-RetryQuitKey count={gt.count("function Read-RetryQuitKey")}')

gm.write_text(gt, encoding='utf-8', newline='\n')
print('patched git-mode.ps1 batch')

# bump version
ver = '20260719.20'
(root / 'scripts/client/windows/connect-version.txt').write_text(ver + '\n', encoding='utf-8')
macv = root / 'scripts/client/mac/connect-version.txt'
if macv.exists():
    macv.write_text(ver + '\n', encoding='utf-8')
cpt = (root / 'scripts/client/windows/connect.ps1').read_text(encoding='utf-8')
cpt2, n = re.subn(r"\$script:ConnectVersion = '20260719\.\d+'", f"$script:ConnectVersion = '{ver}'", cpt, count=1)
if n != 1:
    raise SystemExit(f'version bump fail n={n}')
(root / 'scripts/client/windows/connect.ps1').write_text(cpt2, encoding='utf-8', newline='\n')
print('bumped', ver)
print('DONE')
