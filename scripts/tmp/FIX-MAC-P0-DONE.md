# FIX-MAC-P0-DONE — Mac P0 (`git-mode.sh`)

**Date:** 2026-07-20  
**Scope:** `scripts/client/git-mode.sh` only  
**Deploy:** NO  
**Tooling:** laptop-exec `-p claude-code-server`

## Summary

| # | Fix | Status |
|---|-----|--------|
| 1 | Tunnel wait/poll `seq 1 4` → `seq 1 12` | **PASS** |
| 2 | `recover_mounts_if_needed` one `sshx`, no nested server `sshx` | **PASS** |
| 3 | Sync `banner_miss_tcp_open` increments soft-fail toward DROP | **PASS** |

**OVERALL: PASS**

---

## 1. Tunnel wait loops (`seq 1 12`)

### laptop-exec rg `seq 1 4` (expect empty / exit 1)

```text
exit=1
```

### laptop-exec rg `seq 1 12`

```text
scripts/client/git-mode.sh:877:    for i in $(seq 1 12); do
scripts/client/git-mode.sh:907:    for i in $(seq 1 12); do
```

### Local corroboration

```text
seq 1 4: (no matches)
seq 1 12:
877|    for i in $(seq 1 12); do
907|    for i in $(seq 1 12); do
```

### `wait_for_tunnel_up`

```bash
875|wait_for_tunnel_up() {
876|    local pid="${1:-}" i sleep_s
877|    for i in $(seq 1 12); do
878|        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
879|            if declare -F connect_log >/dev/null 2>&1; then
880|                connect_log "TUNNEL_WAIT fail=1 attempt=$i reason=ssh_died pid=$pid" 'WARN'
881|            fi
882|            printf '    Tunnel check... SSH process died\n'
883|            release_stale_tunnel_port || true
884|            return 1
885|        fi
886|        if tunnel_up; then
887|            if declare -F connect_log >/dev/null 2>&1; then
888|                connect_log "TUNNEL_WAIT ok=1 attempt=$i port=$PORT pid=$pid" 'DEBUG'
889|            fi
890|            return 0
891|        fi
892|        if [ "$i" -ge 12 ]; then
893|            break
894|        fi
895|        sleep_s="$(awk "BEGIN { s=0.25+($i-1)*0.2; print (s>1.5?1.5:s) }")"
896|        if declare -F connect_log >/dev/null 2>&1; then
897|            connect_log "TUNNEL_WAIT ok=0 attempt=$i port=$PORT" 'TRACE'
898|        fi
899|        sleep "$sleep_s"
900|    done
901|    release_stale_tunnel_port || true
902|    return 1
903|}
```

### `poll_tunnel_with_progress` (header + loop bound)

```bash
905|poll_tunnel_with_progress() {
906|    local pid="${1:-}" i sleep_s up=""
907|    for i in $(seq 1 12); do
908|        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
909|            if declare -F connect_log >/dev/null 2>&1; then
910|                connect_log "TUNNEL_WAIT fail=1 attempt=$i reason=ssh_died pid=$pid" 'WARN'
911|            fi
912|            printf '    Tunnel check... SSH process died\n'
913|            release_stale_tunnel_port || true
914|            return 1
915|        fi
916|        if tunnel_up; then
917|            if declare -F connect_log >/dev/null 2>&1; then
918|                connect_log "TUNNEL_WAIT ok=1 attempt=$i port=$PORT pid=$pid" 'DEBUG'
919|            fi
920|            if [ "$i" -eq 1 ]; then
921|                printf '    Tunnel check... port %d is open\n' "$PORT"
922|            else
923|                printf '    Tunnel check %d/12... port %d is open\n' "$i" "$PORT"
924|            fi
925|            return 0
926|        fi
927|        if [ "$i" -ge 12 ]; then
928|            break
929|        fi
```

---

## 2. `recover_mounts_if_needed` — single remote command

### laptop-exec rg `recover-one`

```text
scripts/client/git-mode.sh:1017:    if ! sshx "timeout 30 $CM recover-one '$id' 2>/dev/null || timeout 30 $CM recover-if-needed '$id' 2>/dev/null || timeout 30 $CM recover 2>/dev/null || true"; then
```

### Function body

```bash
1002|recover_mounts_if_needed() {
1003|    local id="$1" fresh_tunnel="${2:-0}" recover_ec=0 recover_begin recover_ms
1004|    if [ "$fresh_tunnel" = "0" ] && project_mount_healthy "$id"; then
1005|        if [ "$(get_git_mode)" = "off" ]; then
1006|            sshx "timeout 15 $CM recover-if-needed '$id' 2>/dev/null" 2>/dev/null || true
1007|        fi
1008|        return 0
1009|    fi
1010|    printf '    \033[0;90mRecovering stale mounts...\033[0m\n'
1011|    recover_begin=$SECONDS
1012|    if declare -F connect_log >/dev/null 2>&1; then
1013|        connect_log "RECOVER: begin project=$id fresh_tunnel=$fresh_tunnel" 'INFO'
1014|    fi
1015|    clear_tunnel_banner_cache
1016|    # Single remote command (Win parity) — no nested sshx on the server.
1017|    if ! sshx "timeout 30 $CM recover-one '$id' 2>/dev/null || timeout 30 $CM recover-if-needed '$id' 2>/dev/null || timeout 30 $CM recover 2>/dev/null || true"; then
1018|        recover_ec=$?
1019|    fi
1020|    recover_ms=$(( (SECONDS - recover_begin) * 1000 ))
1021|    if declare -F connect_log >/dev/null 2>&1; then
1022|        if [ "$recover_ec" -ne 0 ]; then
1023|            connect_log "RECOVER: fail project=$id exit=$recover_ec ms=$recover_ms" 'WARN'
1024|        else
1025|            connect_log "RECOVER: end project=$id ms=$recover_ms" 'INFO'
1026|        fi
1027|    fi
1028|    if [ "$recover_ec" -ne 0 ]; then
1029|        printf '    \033[0;33mRecover finished with errors (exit %s)\033[0m\n' "$recover_ec"
1030|    else
1031|        printf '    \033[0;90mRecover done\033[0m\n'
1032|    fi
1033|}
```

Pass: ONE local `sshx`; remote is `timeout 30 $CM recover-one || … recover-if-needed || … recover`.  
Fail pattern absent: `timeout 30 sshx "$CM recover-one` (nested server sshx).

---

## 3. Sync softfail `banner_miss` → budget DROP

### laptop-exec rg `banner_miss_tcp_open`

```text
scripts/client/git-mode.sh:838:                connect_log "TUNNEL_SYNC soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/6 pid=$bg_pid port=$PORT reason=banner_miss_tcp_open" 'WARN'
scripts/client/git-mode.sh:842:                    connect_log "TUNNEL_DROP pid=$bg_pid port=$PORT reason=banner_miss_tcp_open_budget count=$_TUNNEL_SOFT_FAIL_COUNT" 'WARN'
scripts/client/git-mode.sh:1132:            connect_log "ENSURE_TUNNEL soft_fail pid=$bg_pid port=$PORT reason=banner_miss_tcp_open action=reseed" 'WARN'
```

### laptop-exec rg `banner_miss_tcp_open_budget`

```text
scripts/client/git-mode.sh:842:                    connect_log "TUNNEL_DROP pid=$bg_pid port=$PORT reason=banner_miss_tcp_open_budget count=$_TUNNEL_SOFT_FAIL_COUNT" 'WARN'
```

### Sync block

```bash
832|    fi
833|    if [ "$probe_up" -eq 0 ]; then
834|        if declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; then
835|            _TUNNEL_SOFT_FAIL_COUNT=$(( ${_TUNNEL_SOFT_FAIL_COUNT:-0} + 1 ))
836|            _TUNNEL_SYNC_FAIL_COUNT=0
837|            if declare -F connect_log >/dev/null 2>&1; then
838|                connect_log "TUNNEL_SYNC soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/6 pid=$bg_pid port=$PORT reason=banner_miss_tcp_open" 'WARN'
839|            fi
840|            if [ "$_TUNNEL_SOFT_FAIL_COUNT" -ge 6 ]; then
841|                if declare -F connect_log >/dev/null 2>&1; then
842|                    connect_log "TUNNEL_DROP pid=$bg_pid port=$PORT reason=banner_miss_tcp_open_budget count=$_TUNNEL_SOFT_FAIL_COUNT" 'WARN'
843|                fi
844|                release_stale_tunnel_port || true
845|                _TUNNEL_SOFT_FAIL_COUNT=0
846|                return 1
847|            fi
848|            return 0
849|        else
850|            _TUNNEL_SYNC_FAIL_COUNT=$(( _TUNNEL_SYNC_FAIL_COUNT + 1 ))
```

Behavior:
- Increment `_TUNNEL_SOFT_FAIL_COUNT` on each banner_miss + TCP open
- Log `count=N/6 … reason=banner_miss_tcp_open`
- At `>= 6`: `TUNNEL_DROP … reason=banner_miss_tcp_open_budget` + return 1

---

## Checklist

- [x] Zero `seq 1 4` in `git-mode.sh`
- [x] Two `seq 1 12` in wait/poll
- [x] Recover: one `sshx` with remote `timeout 30 $CM recover-one …`
- [x] No nested `timeout 30 sshx "$CM recover-one`
- [x] Sync banner_miss increments `_TUNNEL_SOFT_FAIL_COUNT` toward DROP
- [x] No deploy performed
