# TEST-HARD-3 — Tunnel P0 Contract Verification (Agent T3)

**Date:** 2026-07-20  
**Project:** `claude-code-server` (laptop-exec `-p claude-code-server` only)  
**Tunnel:** UP (port 21002, laptop_user=Smart, laptop_os=windows)  
**Deploy:** None

## Method

- `laptop-exec rg -p claude-code-server …` for static contract patterns
- `laptop-exec run -p claude-code-server -- powershell -NoProfile -File scripts/tmp/test-tunnel-contracts.ps1`

---

## P0 Checklist

### 1. git-mode.sh: `seq 1 12` present; `seq 1 4` ABSENT

| Check | Result | Evidence |
|-------|--------|----------|
| `seq 1 12` present | **PASS** | `scripts/client/git-mode.sh:909` (`wait_for_tunnel_up`), `:939` (`poll_tunnel_with_progress`) |
| `seq 1 4` absent | **PASS** | `laptop-exec rg … "seq 1 4" scripts/client/` → exit 1, zero matches |

```909:909:scripts/client/git-mode.sh
    for i in $(seq 1 12); do
```

```939:939:scripts/client/git-mode.sh
    for i in $(seq 1 12); do
```

---

### 2. git-mode.sh recover: single sshx recover-one line (no nested `timeout 30 sshx`)

| Check | Result | Evidence |
|-------|--------|----------|
| Single `sshx` with `recover-one` | **PASS** | `scripts/client/git-mode.sh:1048-1049` |
| No nested `timeout 30 sshx` | **PASS** | `laptop-exec rg … "timeout 30 sshx" scripts/client/git-mode.sh` → exit 1, zero matches |

```1047:1049:scripts/client/git-mode.sh
    clear_tunnel_banner_cache
    # Single remote command (Win parity) - no nested sshx on the server.
    if ! sshx "timeout 30 $CM recover-one '$id' 2>/dev/null || timeout 30 $CM recover-if-needed '$id' 2>/dev/null || timeout 30 $CM recover 2>/dev/null || true"; then
```

---

### 3. git-mode.ps1: SoftFailCount++ toward DROP for banner_miss; TUNNEL_DROP banner_miss_tcp_open_budget; Ensure action=reseed

| Check | Result | Evidence |
|-------|--------|----------|
| `TunnelSoftFailCount++` on banner_miss | **PASS** | `:605` (Sync-SessionTunnelProcess), `:990` (Ensure-SessionTunnel) |
| `-ge 6` → `banner_miss_tcp_open_budget` DROP | **PASS** | `:608-613`, `:992-997` |
| Ensure path logs `action=reseed` | **PASS** | `:991` |

```605:613:scripts/client/git-mode.ps1
                    $script:TunnelSoftFailCount++
                    Write-GitModeLog ("TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open$(Get-TunnelSessionDiagSuffix)") 'WARN'
                    $script:TunnelSyncFailCount = 0
                    if ($script:TunnelSoftFailCount -ge 6) {
                        Write-TunnelDropLog -Reason 'banner_miss_tcp_open_budget' -Pid $BgTunnel.Value.Id `
                            -TcpOpen $true -Banner $script:TunnelBannerCacheBanner
                        Release-StaleTunnelPort
                        $script:TunnelSoftFailCount = 0
                        return $false
```

```990:999:scripts/client/git-mode.ps1
            $script:TunnelSoftFailCount++
            Write-GitModeLog ("ENSURE_TUNNEL soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed$(Get-TunnelSessionDiagSuffix)") 'WARN'
            if ($script:TunnelSoftFailCount -ge 6) {
                Write-TunnelDropLog -Reason 'banner_miss_tcp_open_budget' -Pid $BgTunnel.Value.Id `
                    -TcpOpen $true -Banner $script:TunnelBannerCacheBanner
                Release-StaleTunnelPort
                $script:TunnelSoftFailCount = 0
                return $false
            }
            # Fall through to kill stale bg + reseed below.
```

---

### 4. connect.ps1: TUNNEL_DROP auto_reconnect; Begin-ConnectRecovery auto silent update; EditorSeenOpen ≠ editorOpened alone

| Check | Result | Evidence |
|-------|--------|----------|
| `TUNNEL_DROP reason=auto_reconnect` | **PASS** | `scripts/client/windows/connect.ps1:1668` |
| `Begin-ConnectRecovery` auto → `Invoke-ConnectSilentUpdateCheck` | **PASS** | `:643-645` |
| EditorSeenOpen sticky; no force editorOpened alone | **PASS** | `:1739-1740`, `:1752-1753` |

```643:646:scripts/client/windows/connect.ps1
    if ($Trigger -eq 'auto') {
        if (Get-Command Invoke-ConnectSilentUpdateCheck -ErrorAction SilentlyContinue) {
            Invoke-ConnectSilentUpdateCheck
        }
```

```1668:1668:scripts/client/windows/connect.ps1
                        Write-ConnectLog ("TUNNEL_DROP reason=auto_reconnect tunnel_sync_ok={0} project={1} editor_opened={2} editor_seen={3} gen={4}" -f $tunnelSyncOk, $go.Id, $editorOpened, $script:EditorSeenOpen, $script:RecoveryGeneration) 'WARN'
```

```1739:1740:scripts/client/windows/connect.ps1
                        # Transient CIM failure: keep prior sticky only if still marked; do not force editorOpened.
                        if ($script:EditorSeenOpen) {
```

```1752:1753:scripts/client/windows/connect.ps1
                    # Keep EditorSeenOpen if already set by on-folder/window checks; never force editorOpened from sticky alone.
                    if ($editorOpened) { $script:EditorSeenOpen = $true }
```

---

### 5. Contract script: `scripts/tmp/test-tunnel-contracts.ps1`

| Check | Result | Evidence |
|-------|--------|----------|
| Run script | **PASS** | Exit 0 — **13 passed, 0 failed** |

```
=== Tunnel softfail / banner / recover contracts ===
  PASS  Win: SoftFailCount budget threshold (-lt 6) present
  PASS  Win: SoftFailCount -ge 6 leads to TUNNEL_DROP or return $false
  PASS  Mac: SoftFail budget emits TUNNEL_DROP (no_ssh_proc_tcp_open_budget)
  PASS  Win: banner_miss_tcp_open present
  PASS  Mac: banner_miss_tcp_open present
  PASS  Win: banner_miss budgets toward DROP
  PASS  Mac: banner_miss budgets toward DROP
  PASS  Win Ensure-SessionTunnel does NOT return success solely on banner_miss_tcp_open
  PASS  Mac ensure_session_tunnel does NOT return success solely on banner_miss_tcp_open
  PASS  Mac wait_for_tunnel uses seq 1 12 or -le 12
  PASS  Mac: recover_mounts_if_needed body captured
  PASS  Mac recover_mounts_if_needed: single remote command; no nested sshx
  PASS  Win: EditorSeenOpen cleared when editor not open

Contracts: 13 passed, 0 failed
```

---

## OVERALL: **PASS**

All five P0 contract areas verified. No deploy performed.
