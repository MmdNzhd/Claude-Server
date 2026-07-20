from pathlib import Path
p = Path('scripts/client/mac/connect-update.sh')
c = p.read_text(encoding='utf-8')
old = '''_update_file_log() {
  # Harden: ERROR lines always carry FAIL UPDATE_ for greppable day log.
  if [ "${2:-INFO}" = "ERROR" ]; then
    case "$1" in
      FAIL\\ UPDATE_*) ;;
      *) set -- "FAIL UPDATE_: $1" "$2" ;;
    esac
  fi

    local msg="$1" level="${2:-INFO}"
    local sid="${CLAUDE_CONNECT_RUN_ID:--}"
    printf '[%s] [%s] [%s] UPDATE: %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$sid" "$msg" >> "$(_update_log_path)" 2>/dev/null || true
}
'''
# read actual
idx = c.find('_update_file_log()')
end = c.find('\n_verify_checksums', idx)
print(repr(c[idx:end]))
new = '''_update_file_log() {
    local msg="$1" level="${2:-INFO}"
    local sid="${CLAUDE_CONNECT_RUN_ID:--}"
    local ts
    # Harden: ERROR lines always carry FAIL UPDATE_ for greppable day log.
    if [ "$level" = "ERROR" ]; then
        case "$msg" in
            FAIL\ UPDATE_*) ;;
            *) msg="FAIL UPDATE_: $msg" ;;
        esac
    fi
    if command -v python3 >/dev/null 2>&1; then
        ts="$(python3 -c 'import time; t=time.time(); print(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int((t%1)*1000))' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S.000')"
    else
        ts="$(date '+%Y-%m-%d %H:%M:%S.000')"
    fi
    printf '[%s] [%s] [%s] UPDATE: %s\\n' "$ts" "$level" "$sid" "$msg" >> "$(_update_log_path)" 2>/dev/null || true
}
'''
# Use exact from file
old_exact = c[idx:end]
if not old_exact.startswith('_update_file_log()'):
    raise SystemExit('bad slice')
c = c[:idx] + new + c[end:]
p.write_text(c, encoding='utf-8', newline='\n')
print('OK update log fn')

# Fix hard suite - uses $uiSh2 but $win exists; also fix Assert for uiSh2 - already have $uiSh
tp = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
tc = tp.read_text(encoding='utf-8')
tc = tc.replace('$uiSh2 = Get-Content (Join-Path $Client \'connect-ui.sh\') -Raw\nAssert ($uiSh2 -match \'connect_log_ts\')',
                'Assert ($uiSh -match \'connect_log_ts\')')
# if still uiSh2
tc = tc.replace('$uiSh2', '$uiSh')
tp.write_text(tc, encoding='utf-8', newline='\n')
print('OK tests')
