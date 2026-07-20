# Agent V3 - connect.ps1 (Windows)

Scope: `scripts/client/windows/connect.ps1` only. No deploy.

## 1. Structured auto-drop log

Replaced legacy `TUNNEL: connection dropped - auto reconnect` with:

```
TUNNEL_DROP reason=auto_reconnect soft_fail=<count|?> tcp=<bool|?> tunnel_sync_ok=<bool> project=<id|?> editor_opened=<bool> editor_seen=<bool> gen=<n>
```

Best-effort in-scope vars at auto-drop time:

| Field | Source |
|---|---|
| soft_fail | `$script:TunnelSoftFailCount` (git-mode.ps1) |
| tcp | `Test-TunnelPortTcpOpen`, else `Test-TunnelUp`, else `?` |
| tunnel_sync_ok | `$tunnelSyncOk` (false when drop detected) |
| project | `$go.Id` |
| editor_opened | `$editorOpened` |
| editor_seen | `$script:EditorSeenOpen` |
| gen | `$script:RecoveryGeneration` (pre-increment) |

Emits only on automatic drop (no key pressed during tunnel sync failure).

## 2. Silent update on auto recovery

`Begin-ConnectRecovery`:

- After `RECOVERY_BEGIN` log
- When `Trigger -eq 'auto'`, calls `Invoke-ConnectSilentUpdateCheck` if command exists (connect-ui.ps1)
- Manual `Trigger -eq 'manual'` does **not** call it

## 3. Invariants preserved

- ASCII-only log tokens
- Persian keyboard `useVk` logic unchanged (VK fallback only for null/control KeyChar)
