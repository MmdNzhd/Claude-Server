# Agent V4 - Mac connect.sh DONE

File: `scripts/client/mac/connect.sh` only. No deploy.

## 1. CLAUDE_CONNECT_RUN_ID (before connect-update.sh)

- Exported stable 12-char run id before `connect-update.sh` runs.
- Primary: `python3 -c 'import uuid; print(uuid.uuid4().hex[:12])'`
- Fallback: `date +%s$$` when python3/uuid unavailable.
- Preserved across update relaunch via `export CLAUDE_CONNECT_RUN_ID`.

## 2. Early BOOTSTRAP day log

- Appends to `~/.config/claude-connect/logs/connect-YYYYMMDD.log` before update.
- Format matches Windows `connect.bat`:
  `[timestamp] [INFO] [sid] BOOTSTRAP: connect.sh start here=<script_dir>/`
- Sets log file mode 600 when possible.

## 3. Session id alignment

- After `init_connect_log`, sets `CONNECT_SESSION_ID=$CLAUDE_CONNECT_RUN_ID` when length >= 8.
- Correlates BOOTSTRAP / UPDATE / session lines in the day log (parity with Windows connect-ui.ps1).

## 4. Structured TUNNEL_DROP on auto reconnect

Added `log_tunnel_drop_auto_reconnect()` helper. Emits:

- `TUNNEL_DROP pid=<bg_pid> port=<PORT> reason=auto_reconnect [extras]` (WARN)
- `TUNNEL: connection dropped - auto reconnect` (WARN)

Called on session tunnel-drop paths:

- After `tunnel_drop_session_action` when auto `_action=r` (extras: `sync_failed=1`, `proc_dead=1`)
- Fallthrough recover when `_action` still empty (extra: `trigger=fallthrough`)

Field names align with git-mode `TUNNEL_DROP pid= port= reason=` and Windows human line.

Removed duplicate malformed `TUNNEL_DROP reason=auto_reconnect project=...` from recovery handler (logged earlier).

## 5. ensure_openssh_mux_limits

- Remains a top-level function outside `step_ok` (no nested functions).

## 6. ASCII only

- All new strings are ASCII.

## Verify

```bash
bash -n scripts/client/mac/connect.sh
grep -n 'CLAUDE_CONNECT_RUN_ID\|BOOTSTRAP\|log_tunnel_drop_auto_reconnect' scripts/client/mac/connect.sh
```
