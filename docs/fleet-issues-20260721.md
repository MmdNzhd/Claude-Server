# Fleet / backlog status — 2026-07-21

Snapshot after Connect proxy UX backlog implementation (laptop code + Desktop sync; **no** `deploy-client-bundle`).

## Goals addressed

1. Cursor Chat on company LAN without laptop international VPN (fixed ports + owner + never CLEAR + PROXY_HEALTH + sidecar).
2. Tunnel flap / multi-Connect must not wipe proxy or mass-kill windows.
3. UX: `(mounted)` tags, skip remount when healthy, quieter probes.
4. Updates Optional by default (48h defer); Force via `client-update-policy.json`.
5. Fleet visibility in this doc only — no force fleet update.

## Client version

- Target: `20260721.52` (Phase A+B).
- Launch from `Desktop\Claude-Connect` after `sync-desktop.ps1` (do not use stale publish `.49`/`.42` folders).

## Per-user (known; re-verify after Optional update)

| User | Notes |
|------|-------|
| smart | Develop on Claude-Connect `.52`; verify PROXY_HEALTH ok=1, no CLEAR with windows, no LAUNCH_KILL |
| amir | OneDrive path; was `.46` — stays old until Optional update accepted |
| amirhossein | Watch UPDATE_SWAP / relaunch |
| aria | Editor path issues historically |
| mehrdad | path mix / golden_stale |
| others | Aggregate via connect day logs |

## Log patterns to grep

- `CURSOR_PROXY_CLEAR` / `CLEAR_SKIP` / `PROXY_HEALTH` / `CURSOR_PROXY_ALIGN` / `CURSOR_PROXY_OWNER`
- `LAUNCH_KILL` / `auth_relaunch_never_kill` / `hard_refuse`
- `TUNNEL_DROP` / `wait_timeout` / `SIDECAR_START`
- `UPDATE_SWAP_IN_USE` / `UPDATE_OPTIONAL_SKIP` / `UPDATE_FORCE`
- `MOUNT skip_remount`

## Ops (fill at verify time)

```bash
df -h /
free -h
uptime
systemctl is-active xray
```

## Non-goals kept

- No xray VLESS redesign
- No `claude-server deploy-client-bundle` / force fleet ZIP
- Designer connect product left unchanged for remount UX
- Personal `%APPDATA%\Cursor` untouched


## Note on 2026-07-21 sync

`sync-desktop.ps1` called `publish.ps1` which **default-deployed** client bundle `v20260721.52` to Smart and Sepidz `/usr/local/share/claude-client` (unintended vs "no deploy" request). `sync-desktop.ps1` now passes `-SkipServerDeploy` unless `-DeployServer` is set. Policy JSON may still need a future intentional deploy-client-bundle to land in the share.
