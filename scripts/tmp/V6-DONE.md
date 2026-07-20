# V6 DONE - mac/connect-update.sh

Agent: V6 (laptop-exec only, `-p claude-code-server`)

## File owned

- `scripts/client/mac/connect-update.sh`

## Changes

### 1. CLAUDE_CONNECT_RUN_ID in file logs

`_update_file_log` stamps each line with the run id (Windows parity):

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] [RUN_ID] UPDATE: message
```

Uses `CLAUDE_CONNECT_RUN_ID` when set; falls back to `-`.

### 2. CLAUDE_CONNECT_UPDATE_QUIET=1

When `CLAUDE_CONNECT_UPDATE_QUIET=1`:

- Progress/status `printf` output is suppressed via `_update_msg` (update source, retry, available, downloading, success).
- Error paths still write to the day file log via `_update_file_log`; stdout stays minimal or empty.
- Exit codes unchanged (0 / 1 / 2).

### 3. RUN_ID generation

`_ensure_run_id` runs at script startup (before any logging):

- If `CLAUDE_CONNECT_RUN_ID` is already set, export and keep it.
- If empty, generate a 12-char id (`uuidgen`, else `/proc/sys/kernel/random/uuid`, else `epoch+pid` fallback) and `export CLAUDE_CONNECT_RUN_ID`.

## Not in scope

- No deploy (`claude-server install` not run).
- No changes outside `connect-update.sh`.

## Verify (manual)

```bash
unset CLAUDE_CONNECT_RUN_ID
export CLAUDE_CONNECT_UPDATE_QUIET=1
bash scripts/client/mac/connect-update.sh
echo "RUN_ID=$CLAUDE_CONNECT_RUN_ID"
tail -3 ~/.config/claude-connect/logs/connect-$(date +%Y%m%d).log
```

Expect: no user-facing update lines on stdout; log lines include `[RUN_ID]`; `RUN_ID` is non-empty after run.
