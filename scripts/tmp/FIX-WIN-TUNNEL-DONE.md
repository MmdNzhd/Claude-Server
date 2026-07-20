# FIX-WIN-TUNNEL-DONE — Win tunnel softfail + sticky

**When:** 2026-07-20  
**Project:** `-p claude-code-server`  
**Deploy:** NO (code only)

## Summary

Fixed Win tunnel softfail so `banner_miss_tcp_open` budgets SoftFailCount and DROPs at ≥6 instead of resetting healthy. Ensure no longer returns success/reuses a zombie on banner miss. Cleared `EditorSeenOpen` sticky misuse that forced `editorOpened=$true` when the editor was closed.

## Files

| File | Change |
|------|--------|
| `scripts/client/git-mode.ps1` | Sync + Ensure softfail budget / DROP |
| `scripts/client/windows/connect.ps1` | Sticky clear on close; no force-open |

---

## 1. Sync-SessionTunnelProcess — `banner_miss_tcp_open`

### BEFORE (bug)

```powershell
                if ($tcpOpen) {
                    Write-GitModeLog "TUNNEL_SYNC soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
                    $script:TunnelSyncFailCount = 0
                    $script:TunnelSoftFailCount = 0
                } else {
```

Reset SoftFailCount to 0 and fell through as healthy — zombie forward never DROPped.

### AFTER (fix)

```powershell
if ($tcpOpen) {
            $script:TunnelSoftFailCount++
            Write-GitModeLog "TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/6 port=$Port reason=no_proc_tcp_open" 'WARN'
            $null = Try-ReattachSessionTunnelProcess -BgTunnel $BgTunnel
            if ($script:TunnelSoftFailCount -ge 6) {
                Write-GitModeLog "TUNNEL_DROP port=$Port reason=no_proc_tcp_open_budget count=$script:TunnelSoftFailCount" 'WARN'
                Release-StaleTunnelPort
                $script:TunnelSoftFailCount = 0
                $script:TunnelSyncFailCount = 0
                return $false
            }
            $script:TunnelSyncFailCount = 0
            if (-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) {
                return $true
            }
            # Reattached under budget: continue into bg-alive probe path.
        }
    }

    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        $now = Get-Date
        if (-not $script:LastForwardProbeAt) {
            $script:LastForwardProbeAt = $now
        } elseif (($now - $script:LastForwardProbeAt).TotalSeconds -ge 30) {
            $script:LastForwardProbeAt = $now
            $probeUp = $false
            for ($i = 1; $i -le 3; $i++) {
                if ($i -gt 1) { Start-Sleep -Milliseconds 300 }
                if (Test-TunnelUp) { $probeUp = $true; break }
            }
            if (-not $probeUp) {
                $tcpOpen = $false
                try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
                if ($tcpOpen) {
                    $script:TunnelSoftFailCount++
                    Write-GitModeLog "TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
                    $script:TunnelSyncFailCount = 0
                    if ($script:TunnelSoftFailCount -ge 6) {
                        Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open_budget count=$script:TunnelSoftFailCount" 'WARN'
                        Release-StaleTunnelPort
                        $script:TunnelSoftFailCount = 0
                        return $false
                    }
                    return $true
                } else {
```

- Increment SoftFailCount (do **not** reset on banner_miss soft path)
- SoftFailCount ≥ 6 → log `TUNNEL_DROP` reason=`banner_miss_tcp_open_budget` → `return $false`
- Under budget → `return $true` (tolerate transient miss)
- Do **not** reset SoftFailCount on every bg_alive tick (only healthy banner probe)

Also: `no_proc_tcp_open` SoftFail≥6 → `TUNNEL_DROP` / `return $false` before reattach.

---

## 2. Ensure-SessionTunnel — `banner_miss_tcp_open`

### BEFORE (bug)

```powershell
        if ($tcpOpen) {
            # (no TUNNEL_REUSED on banner miss)
            # keep sync fail count; fall through to reseed
            # Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed" 'WARN'
            # Fall through to kill stale bg + reseed below.
        } elseif ($script:LastTunnelSpawnSuccessAt -and $script:LastTunnelSpawnSuccessPort -eq $Port -and
```

Logged soft_fail but did not budget SoftFailCount; concurrent mangled braces / reuse paths could still treat the zombie as success.

### AFTER (fix)

```powershell
if ($tcpOpen) {
            # Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
            $script:TunnelSoftFailCount++
            Write-GitModeLog "ENSURE_TUNNEL soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed" 'WARN'
            if ($script:TunnelSoftFailCount -ge 6) {
                Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open_budget count=$script:TunnelSoftFailCount" 'WARN'
                Release-StaleTunnelPort
                $script:TunnelSoftFailCount = 0
                return $false
            }
            # Fall through to kill stale bg + reseed below.
        } elseif ($script:LastTunnelSpawnSuccessAt -and $script:LastTunnelSpawnSuccessPort -eq $Port -and
```

- Increment SoftFailCount
- SoftFailCount ≥ 6 → `TUNNEL_DROP` + `return $false`
- Under budget → fall through to kill stale bg + reseed (no `TunnelReused`, no success return)
- `elseif` recent_success so banner-miss cannot hit reuse path
- Successful reseed resets SoftFailCount

---

## 3. connect.ps1 — EditorSeenOpen sticky

### BEFORE (bug)

```powershell
            if ($onFolderNow) {
                $editorOpened = $true
                $script:EditorSeenOpen = $true
            } elseif ($script:EditorSeenOpen) {
                $editorOpened = $true   # BUG: force open when editor already closed
            } else {
                $editorOpened = $false
            }

            # recovery:
            $skipRecoveryClear = [bool]($editorOpened -or $script:EditorSeenOpen)
            if ($skipRecoveryClear) {
                $editorOpened = $true
                $script:EditorSeenOpen = $true
            }
```

### AFTER (fix)

Session open clears sticky when window gone:

```powershell
if ($onFolderNow) {
                $editorOpened = $true
                $script:EditorSeenOpen = $true
            } else {
                $windowOpenInit = $false
                if (Get-Command Test-RemoteEditorWindowOpen -ErrorAction SilentlyContinue) {
                    try {
                        $windowOpenInit = [bool](Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                    } catch { $windowOpenInit = $false }
                }
                $editorOpened = $false
                if (-not $windowOpenInit) {
                    if ($script:EditorSeenOpen) {
                        Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=editor_closed phase=session_open' 'INFO'
                    }
                    $script:EditorSeenOpen = $false
                }
            }
```

Recovery does not force `editorOpened` from sticky alone:

```powershell

                Write-Host '    Connection dropped - recovering...' -ForegroundColor Yellow
                if ($skipRecoveryClear) {
                    # Keep EditorSeenOpen if already set by on-folder/window checks; never force editorOpened from sticky alone.
                    if ($editorOpened) { $script:EditorSeenOpen = $true }
                    try {
                        $null = Initialize-SessionBgTunn
```

---

## Verification (post-write)

| Check | Result |
|-------|--------|
| Sync SoftFail++ + DROP budget on banner_miss | PASS |
| Sync no SoftFail reset on banner_miss soft path (without DROP) | PASS |
| Sync no SoftFail reset on every bg_alive | PASS |
| Ensure SoftFail++ + DROP budget | PASS |
| Ensure no TunnelReused on banner_miss | PASS |
| Ensure elseif recent_success | PASS |
| connect no `elseif (EditorSeenOpen) { editorOpened=$true }` | PASS |
| connect EDITOR_SEEN_CLEAR on poll close | PASS |

**Deploy:** not run (per request).
