# FIX-AGENT-DROP-LOG (Agent 3)

Date: 2026-07-20
Deploy: NO

## Goal

Structured `TUNNEL_DROP` lines on tunnel drop / auto-reconnect so session logs explain WHY without guessing. Uses existing `Write-ConnectLog` / `connect_log` session-id stamping (no new sink).

## Structured line contract (Win + Mac parity)

```
TUNNEL_DROP reason=<...> soft_fail=<N> sync_fail=<N> tcp_open=<0|1> tunnel_up=<0|1> tunnel_sync_ok=<true|false> project=<id> editor_opened=<0|1> editor_seen=<0|1> gen=<N> [drop_cause=<sync reason>] [bg_pid=<pid>] [port=<port>] [banner=<...>]
```

- **auto_reconnect** (session loop): `reason=auto_reconnect`; `drop_cause` carries last sync-level reason when set.
- **sync/ensure budget drops**: `reason=no_proc_tcp_open_budget|banner_miss_tcp_open_budget|bg_alive_forward_dead|no_ssh_proc_tunnel_down|tunnel_down`.

## Windows

### `scripts/client/git-mode.ps1`

- **`Write-TunnelDropLog`** (expanded): single helper for sync-level and session-level drops. Logs via `Write-ConnectLog` (not `GITMODE:` prefix). Fields: `soft_fail`, `sync_fail`, `tcp_open`, `tunnel_up`, `tunnel_sync_ok`, `project`, `editor_opened`, `editor_seen`, `gen`, optional `drop_cause`, `bg_pid`, `banner`.
- **`Get-TunnelSessionDiagSuffix`**: appends `project=... soft_fail=... sync_fail=...` to `TUNNEL_SYNC` / `ENSURE_TUNNEL soft_fail` WARN lines.
- **`$script:LastTunnelSyncDropReason`**: set on sync/ensure hard drops; consumed by `auto_reconnect` lines as `drop_cause`.
- Existing `Sync-SessionTunnelProcess` / `Ensure-SessionTunnel` budget paths call `Write-TunnelDropLog` (replacing bare `TUNNEL_DROP` gitmode strings).

### `scripts/client/windows/connect.ps1`

- Auto-reconnect path (no key during drop) calls **`Write-TunnelDropLog -Reason auto_reconnect`** with in-scope `$tunnelSyncOk`, `$go.Id`, `$editorOpened`, `$script:EditorSeenOpen`, `$script:RecoveryGeneration`, `$bgTunnel.Id`.
- Removed legacy `TUNNEL: connection dropped - auto reconnect` one-liner.

## Mac

### `scripts/client/git-mode.sh`

- **`log_tunnel_drop`**: bash helper; same field names as Windows.
- **`_tunnel_session_diag_suffix`**: project + counter suffix for soft_fail WARN lines.
- **`LAST_TUNNEL_SYNC_DROP_REASON`**: set before sync-level `log_tunnel_drop` calls.
- **`sync_session_tunnel_forward`**: budget drops call `log_tunnel_drop`; soft_fail lines include project + counters.
- **`ensure_session_tunnel`**: `ENSURE_TUNNEL soft_fail` includes project + counters.
- **`tunnel_drop_session_action`**: calls `log_tunnel_drop auto_reconnect` when defaulting to `_action=r`.

### `scripts/client/mac/connect.sh`

- Removed **`log_tunnel_drop_auto_reconnect`** and duplicate fallthrough logging (now centralized in `git-mode.sh` helpers).

## Recovery paths

- `RECOVERY_BEGIN` / `RECOVERY_END` / `RECOVERY_STATE_RESET` unchanged (already present from prior agents).
- Auto-reconnect `TUNNEL_DROP` is emitted at drop detection; sync layer may have logged an earlier budget drop with specific `reason=` — session line adds `drop_cause` for linkage.

## Verification (local, no deploy)

```bash
laptop-exec rg -p claude-code-server "Write-TunnelDropLog|log_tunnel_drop|TUNNEL_DROP reason=auto_reconnect" scripts/client/
laptop-exec rg -p claude-code-server "TUNNEL: connection dropped|log_tunnel_drop_auto_reconnect" scripts/client/  # expect no matches
```

Optional: `scripts/client/tests/test-connect-pipeline.ps1` (asserts `TunnelSyncFailCount`, `RECOVERY_BEGIN` still pass).

## Files touched (Agent 3 scope)

| File | Change |
|------|--------|
| `scripts/client/git-mode.ps1` | Expanded `Write-TunnelDropLog`, diag suffix, soft_fail project+counters |
| `scripts/client/windows/connect.ps1` | Auto-reconnect uses `Write-TunnelDropLog` |
| `scripts/client/git-mode.sh` | `log_tunnel_drop`, diag suffix, sync/ensure/tunnel_drop wiring |
| `scripts/client/mac/connect.sh` | Remove duplicate auto-reconnect logger |
