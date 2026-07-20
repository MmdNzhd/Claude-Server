# FIX-MAC-P1 — Mac remaining P1 checklist

Date: 2026-07-20  
Scope: `scripts/client/mac/connect.sh`, `scripts/client/git-mode.sh`  
Method: laptop-exec `-p claude-code-server` only (no deploy)

## Summary

| # | Item | Result |
|---|------|--------|
| 1 | Abort/quit: `push_server_connect_conf --clear` | **PASS** |
| 2 | Fallthrough: set `action=r` before preserve/clear handler | **PASS** |
| 3 | Post-recover: `tunnel_up`/banner not PID-only | **PASS** |
| 4 | `CLEAR_MOUNT Reason=` on Mac | **PASS** |
| 5 | `push_server_connect_conf` fails without `PUSH_CONF_RESULT` | **PASS** |

---

## 1. Abort/quit `--clear` — PASS

`676:push_server_connect_conf --clear`
`720:push_server_connect_conf --clear`
`786:push_server_connect_conf --clear`

Also `clear_session_mount` → `push_server_connect_conf --clear` at git-mode.sh:358.

---

## 2. Fallthrough `action=r` — PASS

`1017:connect_log 'SESSION: fallthrough_recover reason=tunnel_down_empty_action' 'WARN'`
`1019:_action="r"`

Flows into `if [ "$_action" = "r" ]` preserve/clear policy (skip_recovery_clear / auto_recovery).

---

## 3. Post-recover `tunnel_up` — PASS

`690:recover_mounts_if_needed "$go_id" "$(( TUNNEL_REUSED ^ 1 ))"`
`693:if ! tunnel_up; then`
`694:printf '      -> tunnel dropped during recover, restarting...\n'`
`749:if ! tunnel_up; then`

Post-sshd path also uses `tunnel_up` (not PID-only):

`748:# Banner/TCP, not PID-only (Win Test-TunnelUp parity).`
`749:if ! tunnel_up; then`
`750:printf '      -> tunnel dropped after sshd restart, restarting...\n'`

---

## 4. CLEAR_MOUNT `Reason=` — PASS

Function:

`335:clear_session_mount() {`
`336:local project_id="$1" editor_cmd="${2:-}" alias_name="${3:-}" remote_path="${4:-}" skip_editor="${5:-0}" reason="${6:-}"`
`337:local reason_part="" down_begin down_ms`
`338:[ -n "$reason" ] && reason_part=" reason=$reason"`
`339:if declare -F connect_log >/dev/null 2>&1; then`
`340:connect_log "CLEAR_MOUNT project=$project_id skip_editor=$skip_editor editor=$editor_cmd path=$remote_path$reason_part" 'INFO'`

Callers:

`619:clear_session_mount "$go_id" "$EDITOR_CMD" "$ALIAS" "$go_path" 0 'unexpected_disconnect'`
`1093:clear_session_mount "$go_id" "" "$ALIAS" "$go_path" 1 'auto_recovery'`
`1107:clear_session_mount "$go_id" "$EDITOR_CMD" "$ALIAS" "$go_path" 0 'user_quit'`

---

## 5. Fail without PUSH_CONF_RESULT — PASS

`134:# Do not swallow sshx failures with || true - need real exit for RESULT/dedupe gate.`
`135:push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null)"`
`136:push_ec=$?`
`137:result_line="$(printf '%s' "$push_out" | grep PUSH_CONF_RESULT | tail -1 | tr '\n' ' ')"`
`138:if [ "$push_ec" -ne 0 ] || [ -z "$result_line" ]; then`
`139:if declare -F connect_log >/dev/null 2>&1; then`
`140:connect_log "PUSH_CONF fail exit=$push_ec out=${result_line:-no_result} $(printf '%s' "$push_out" | tr '\n' ' ')" 'ERROR'`
`141:fi`
`142:# Do not record dedupe on failure — allow immediate retry.`
`143:if [ "$push_ec" -ne 0 ]; then`
`144:return "$push_ec"`
`145:fi`
`146:return 1`

---

## Invariants preserved

`877:for i in $(seq 1 12); do`
`907:for i in $(seq 1 12); do`
`1017:if ! sshx "timeout 30 $CM recover-one '$id' 2>/dev/null || timeout 30 $CM recover-if-needed '$id' 2>/dev/null || timeout 30 $CM recover 2>/dev/null || true"; then`

## Changes this pass

- `connect.sh`: post-sshd `_tunnel_alive` → `tunnel_up`; restore Reason args on clear_session_mount callers (`unexpected_disconnect`, `auto_recovery`, `user_quit`).
- `git-mode.sh`: items 4–5 already present (Reason= + return 1 on missing RESULT); not reverted.
- No deploy.
