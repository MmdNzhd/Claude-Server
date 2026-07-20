from pathlib import Path
p = Path(r'D:/Smart/Claude-Code-Server/scripts/client/mac/connect.sh')
# read via stdin from laptop-exec instead - this script runs ON laptop
import sys
text = Path(sys.argv[1]).read_text(encoding='utf-8')
bad = '''step_ok()   {

ensure_openssh_mux_limits() {
  # Multi-agent: raise mux channel limits before sshd restart/tunnel.
  local cfg="/etc/ssh/sshd_config"
  [ -f "$cfg" ] || return 0
  if grep -qE '^#?MaxSessions[[:space:]]+' "$cfg" 2>/dev/null; then
    sudo sed -i.bak -E 's/^#?MaxSessions[[:space:]]+[0-9]+/MaxSessions 32/' "$cfg" 2>/dev/null || true
  else
    echo 'MaxSessions 32' | sudo tee -a "$cfg" >/dev/null 2>&1 || true
  fi
  if grep -qE '^#?MaxStartups[[:space:]]+' "$cfg" 2>/dev/null; then
    sudo sed -i.bak -E 's/^#?MaxStartups[[:space:]]+\\S+/MaxStartups 20:50:100/' "$cfg" 2>/dev/null || true
  else
    echo 'MaxStartups 20:50:100' | sudo tee -a "$cfg" >/dev/null 2>&1 || true
  fi
}

    local ms=0 detail="${1:-ok}"
    [ -n "${CURRENT_STEP_START:-}" ] && ms=$(( SECONDS - CURRENT_STEP_START ))
    if declare -F connect_log >/dev/null 2>&1 && [ -n "${CURRENT_STEP_NAME:-}" ]; then
        connect_log "STEP end: $CURRENT_STEP_NAME ok ms=$ms detail=$detail"
    fi
    if [ -n "${1:-}" ]; then printf ' %s\\n' "$*"; else printf ' ok\\n'; fi
}'''
good = '''ensure_openssh_mux_limits() {
  # Multi-agent: raise mux channel limits before sshd restart/tunnel.
  local cfg="/etc/ssh/sshd_config"
  [ -f "$cfg" ] || return 0
  if grep -qE '^#?MaxSessions[[:space:]]+' "$cfg" 2>/dev/null; then
    sudo sed -i.bak -E 's/^#?MaxSessions[[:space:]]+[0-9]+/MaxSessions 32/' "$cfg" 2>/dev/null || true
  else
    echo 'MaxSessions 32' | sudo tee -a "$cfg" >/dev/null 2>&1 || true
  fi
  if grep -qE '^#?MaxStartups[[:space:]]+' "$cfg" 2>/dev/null; then
    sudo sed -i.bak -E 's/^#?MaxStartups[[:space:]]+\\S+/MaxStartups 20:50:100/' "$cfg" 2>/dev/null || true
  else
    echo 'MaxStartups 20:50:100' | sudo tee -a "$cfg" >/dev/null 2>&1 || true
  fi
}

step_ok()   {
    local ms=0 detail="${1:-ok}"
    [ -n "${CURRENT_STEP_START:-}" ] && ms=$(( SECONDS - CURRENT_STEP_START ))
    if declare -F connect_log >/dev/null 2>&1 && [ -n "${CURRENT_STEP_NAME:-}" ]; then
        connect_log "STEP end: $CURRENT_STEP_NAME ok ms=$ms detail=$detail"
    fi
    if [ -n "${1:-}" ]; then printf ' %s\\n' "$*"; else printf ' ok\\n'; fi
}'''
if bad not in text:
    print('PATTERN_MISS')
    # show nearby
    i = text.find('step_ok()')
    print(repr(text[i:i+200]))
    sys.exit(1)
Path(sys.argv[1]).write_text(text.replace(bad, good, 1), encoding='utf-8', newline='\n')
print('FIXED')
