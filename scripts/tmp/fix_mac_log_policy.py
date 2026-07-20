from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.sh')
t = p.read_text(encoding='utf-8')
old = '''connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    printf '[%s] [%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "${CONNECT_SESSION_ID:--}" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true
    CONNECT_LOG_LINES_SINCE_SYNC=$(( ${CONNECT_LOG_LINES_SINCE_SYNC:-0} + 1 ))
    if [ "$level" = "WARN" ] || [ "$level" = "ERROR" ] || [ "${CONNECT_LOG_LINES_SINCE_SYNC:-0}" -ge 1 ]; then
        sync_connect_log_to_server || true
    fi
}'''
new = '''connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    printf '[%s] [%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "${CONNECT_SESSION_ID:--}" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true
    # Local always complete. Sync carefully (parity with Windows connect-ui.ps1):
    # - TRACE/DEBUG stay local-only during hot loops
    # - WARN/ERROR flush now; INFO every 25 lines
    if [ "$level" = "TRACE" ] || [ "$level" = "DEBUG" ]; then
        return 0
    fi
    CONNECT_LOG_LINES_SINCE_SYNC=$(( ${CONNECT_LOG_LINES_SINCE_SYNC:-0} + 1 ))
    if [ "$level" = "WARN" ] || [ "$level" = "ERROR" ] || [ "${CONNECT_LOG_LINES_SINCE_SYNC:-0}" -ge 25 ]; then
        sync_connect_log_to_server || true
    fi
}'''
if old not in t:
    raise SystemExit('old connect_log block not found')
p.write_text(t.replace(old, new, 1), encoding='utf-8', newline='\n')
print('mac connect_log policy fixed')
