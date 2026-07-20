from pathlib import Path

# --- mac/connect.sh ---
p = Path('scripts/client/mac/connect.sh')
c = p.read_text(encoding='utf-8')

old_boot = """printf '[%s] [INFO] [%s] BOOTSTRAP: connect.sh start here=%s\\n' \\
    "$(date '+%Y-%m-%d %H:%M:%S')" "${CLAUDE_CONNECT_RUN_ID:--}" \\
    "$_here_early" >> "$_bootstrap_log_file" 2>/dev/null || true"""

new_boot = """_boot_ts="$(python3 -c 'import time; t=time.time(); print(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int((t%1)*1000))' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S.000')"
printf '[%s] [INFO] [%s] BOOTSTRAP: connect.sh start here=%s\\n' \\
    "$_boot_ts" "${CLAUDE_CONNECT_RUN_ID:--}" \\
    "$_here_early" >> "$_bootstrap_log_file" 2>/dev/null || true"""

if old_boot not in c:
    raise SystemExit('bootstrap block not found')
c = c.replace(old_boot, new_boot, 1)

# unreachable after 10 attempts
old_unreach = """if [ -z "$connected" ] && [ -z "$needs_key" ]; then
    echo ""
    warn "Cannot reach $SERVER_IP after 10 attempts"
    warn "VPN connected? Server running?"
    echo ""; exit 1
fi"""
new_unreach = """if [ -z "$connected" ] && [ -z "$needs_key" ]; then
    echo ""
    warn "Cannot reach $SERVER_IP after 10 attempts"
    warn "VPN connected? Server running?"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "FAIL CONNECT_UNREACHABLE: host=$SERVER_IP attempts=10" 'ERROR'
    fi
    echo ""; exit 1
fi"""
if old_unreach not in c:
    raise SystemExit('unreach block not found')
c = c.replace(old_unreach, new_unreach, 1)

# bare exits after step_fail already have FAIL STEP; EXIT trap adds FAIL EXIT.
# Still tag intentional post-setup abort and foreign session:
old_saved = """            printf '    \\033[0;32mSaved. Re-run connect.sh.\\033[0m\\n'
        fi
        echo ""; exit 1
    fi"""
new_saved = """            printf '    \\033[0;32mSaved. Re-run connect.sh.\\033[0m\\n'
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "FAIL SETUP_RERUN: username saved - user must re-run connect.sh" 'ERROR'
            fi
        fi
        echo ""; exit 1
    fi"""
if old_saved not in c:
    raise SystemExit('saved rerun block not found')
c = c.replace(old_saved, new_saved, 1)

old_foreign = """if ! warn_foreign_server_session; then
    exit 1
fi"""
new_foreign = """if ! warn_foreign_server_session; then
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "FAIL FOREIGN_SESSION: user aborted after foreign server-session warning" 'ERROR'
    fi
    exit 1
fi"""
if old_foreign not in c:
    raise SystemExit('foreign block not found')
c = c.replace(old_foreign, new_foreign, 1)

# Remote Login / key / server setup already step_fail; add explicit FAIL EXIT before exit for clarity when trap races
for needle, tag in [
    ('step_fail "could not enable Remote Login automatically"\n            exit 1',
     'step_fail "could not enable Remote Login automatically"\n            if declare -F connect_log >/dev/null 2>&1; then connect_log "FAIL EXIT reason=remote_login_enable code=1" "ERROR"; fi\n            exit 1'),
    ('step_fail "could not create key"; exit 1',
     'step_fail "could not create key"\n    if declare -F connect_log >/dev/null 2>&1; then connect_log "FAIL EXIT reason=ssh_key_create code=1" "ERROR"; fi\n    exit 1'),
    ('    step_fail "${INIT_SERVER_SESSION_ERROR:-could not configure server (port/key)}"\n    warn "Tip: confirm server username with: bash connect.sh --setup"\n    exit 1',
     '    step_fail "${INIT_SERVER_SESSION_ERROR:-could not configure server (port/key)}"\n    warn "Tip: confirm server username with: bash connect.sh --setup"\n    if declare -F connect_log >/dev/null 2>&1; then connect_log "FAIL EXIT reason=server_setup code=1" "ERROR"; fi\n    exit 1'),
]:
    if needle not in c:
        raise SystemExit(f'exit tag needle missing: {needle[:60]}')
    c = c.replace(needle, tag, 1)

p.write_text(c, encoding='utf-8', newline='\n')
print('OK mac/connect.sh')

# --- designer Mac: minimal connect_log stubs if missing ---
dp = Path('scripts/client/users/designer/connect.sh')
if dp.exists():
    dc = dp.read_text(encoding='utf-8')
    if 'connect_log' not in dc and 'FAIL DIE' not in dc:
        # inject after shebang/header a tiny day-log helper
        inject = '''
# Minimal day-log (designer has no connect-ui.sh). Greppable FAIL for multi-agent diagnosis.
_designer_log() {
    local msg="$1" level="${2:-INFO}"
    local day="$HOME/.config/claude-connect/logs"
    local f="$day/connect-$(date +%Y%m%d).log"
    local sid="${CLAUDE_CONNECT_RUN_ID:--}"
    local ts
    mkdir -p "$day" 2>/dev/null || true
    ts="$(python3 -c 'import time; t=time.time(); print(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int((t%1)*1000))' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S.000')"
    printf '[%s] [%s] [%s] %s\\n' "$ts" "$level" "$sid" "$msg" >> "$f" 2>/dev/null || true
}
'''
        # find die()
        if 'die()' in dc or 'die() {' in dc:
            # replace die body to log
            import re
            dc2, n = re.subn(
                r'die\(\)\s*\{[^}]*\}',
                'die() {\n    _designer_log "ERROR: $*" ERROR\n    _designer_log "FAIL DIE: $*" ERROR\n    echo ""; echo "  [X] $*"; echo ""; exit 1\n}',
                dc, count=1, flags=re.S)
            if n:
                dc = dc2
                # insert helper before die
                idx = dc.find('die()')
                dc = dc[:idx] + inject + '\n' + dc[idx:]
                dp.write_text(dc, encoding='utf-8', newline='\n')
                print('OK designer connect.sh die+log')
            else:
                print('WARN designer die replace failed')
        else:
            print('WARN no die() in designer connect.sh')
    else:
        print('designer already has connect_log/FAIL DIE')

# harden hard suite section H with new mac asserts
tp = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
tc = tp.read_text(encoding='utf-8')
marker = "Assert ($uiSh -match 'connect_log_ts')"
extra = r'''
Assert ($uiSh -match 'connect_log_ts') 'Mac connect_log has millisecond timestamps helper'
Assert ((Get-Content (Join-Path $Client 'mac\connect.sh') -Raw) -match 'FAIL CONNECT_UNREACHABLE') 'Mac unreachable logs FAIL CONNECT_UNREACHABLE'
Assert ((Get-Content (Join-Path $Client 'mac\connect.sh') -Raw) -match '_boot_ts') 'Mac BOOTSTRAP uses ms timestamp'
Assert ((Get-Content (Join-Path $Client 'mac\connect-update.sh') -Raw) -match 'FAIL UPDATE_') 'Mac update ERROR prefixed FAIL UPDATE_'
'''
if "FAIL CONNECT_UNREACHABLE') 'Mac unreachable" not in tc:
    if marker not in tc:
        # find section H end
        if "Mac connect_log has millisecond" in tc:
            tc = tc.replace(
                "Assert ($uiSh -match 'connect_log_ts') 'Mac connect_log has millisecond timestamps helper'",
                extra.strip(),
                1)
        else:
            raise SystemExit('cannot find H marker')
    else:
        tc = tc.replace(marker + " 'Mac connect_log has millisecond timestamps helper'", extra.strip(), 1)
        if "FAIL CONNECT_UNREACHABLE" not in tc:
            tc = tc.replace(marker, extra.strip(), 1)
    tp.write_text(tc, encoding='utf-8', newline='\n')
    print('OK hard suite H asserts')
else:
    print('hard suite already has mac unreach assert')

print('DONE')
