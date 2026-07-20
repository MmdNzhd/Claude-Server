# Agent V8 - TUNNEL_DROP log enrichment (git-mode.ps1)

## Scope
- File: `scripts/client/git-mode.ps1` only
- No deploy

## Change
Added `Write-TunnelDropLog` helper (after `Write-GitModeLog`) to emit a consistent
diagnostic line for every tunnel drop. All four inline `TUNNEL_DROP` `Write-GitModeLog`
calls now route through it.

## Log format
Example:
```
GITMODE: TUNNEL_DROP port=21002 pid=12345 reason=banner_miss_tcp_open_budget soft_fail=6 sync_miss=0 tcp=open banner=(empty)
```

Fields (when known):
| Field | Source |
|-------|--------|
| port | `$Port` |
| pid | bg tunnel process, or last exit pid for no-proc drops |
| reason | unchanged tags: `no_proc_tcp_open_budget`, `banner_miss_tcp_open_budget`, `bg_alive_forward_dead` |
| soft_fail | `$script:TunnelSoftFailCount` |
| sync_miss | `$script:TunnelSyncFailCount` |
| tcp | `open` / `closed` from probe at drop site |
| banner | cache banner or `(empty)` |

## Session id
`Write-GitModeLog` delegates to `Write-ConnectLog` (connect-ui.ps1), which stamps
`[$sid]` on every line. No duplicate session handling added here.

## Call sites updated
1. `Sync-SessionTunnelProcess` - `no_proc_tcp_open_budget`
2. `Sync-SessionTunnelProcess` - `banner_miss_tcp_open_budget`
3. `Sync-SessionTunnelProcess` - `bg_alive_forward_dead`
4. `Ensure-SessionTunnel` - `banner_miss_tcp_open_budget`

## ASCII
All new strings are ASCII-only.
