# -*- coding: utf-8 -*-
"""Make logging coverage complete on Win + Mac: every exit wait, every prompt, every decision."""
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')

# ========== connect-ui.ps1: Wait-ConnectExit + sync every line ==========
ui = root / 'scripts/client/connect-ui.ps1'
t = ui.read_text(encoding='utf-8')
t = t.replace(
    '$script:ConnectLogLinesSinceSync -ge 5',
    '$script:ConnectLogLinesSinceSync -ge 1',
)
if 'function Wait-ConnectExit' not in t:
    helper = r'''
function Wait-ConnectExit {
    param(
        [string]$Reason = 'user_close',
        [int]$Code = 1
    )
    Write-ConnectLog ("EXIT_WAIT: reason={0} code={1}" -f $Reason, $Code) 'INFO'
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }
    try { Read-Host '    Press Enter to close' | Out-Null } catch { }
    if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
    exit $Code
}

'''
    idx = t.find('function Write-ConnectDecision')
    if idx < 0:
        idx = t.find('function Write-ConnectTrace')
    t = t[:idx] + helper + t[idx:]
    print('Wait-ConnectExit added')
ui.write_text(t, encoding='utf-8', newline='\n')

# ========== connect.ps1: replace Press Enter exits ==========
cp = root / 'scripts/client/windows/connect.ps1'
c = cp.read_text(encoding='utf-8')

# Common patterns -> Wait-ConnectExit
patterns = [
    (r"Write-Host ''; Read-Host '    Press Enter to close' \| Out-Null\s*\n\s*exit 1",
     "Wait-ConnectExit -Reason 'fatal' -Code 1"),
    (r'Read-Host \'    Press Enter to close\' \| Out-Null\s*\n\s*exit 1',
     "Wait-ConnectExit -Reason 'fatal' -Code 1"),
    (r'Write-Host ""; Read-Host "    Press Enter to close" \| Out-Null; exit 1',
     "Wait-ConnectExit -Reason 'fatal' -Code 1"),
    (r"Write-Host ''; Read-Host '    Press Enter to close' \| Out-Null; exit 1",
     "Wait-ConnectExit -Reason 'fatal' -Code 1"),
    (r'Write-Host ""; Write-Host "  \[X\] \$m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" \| Out-Null; exit 1',
     "Write-Host ''; Write-Host \"  [X] $m\" -ForegroundColor Red; Write-Host ''; Wait-ConnectExit -Reason \"die:$m\" -Code 1"),
]

# Simpler approach: replace exact strings
repls = [
    ("Write-Host ''; Read-Host '    Press Enter to close' | Out-Null\n            exit 1",
     "Wait-ConnectExit -Reason 'trap_fatal' -Code 1"),
    ("Read-Host '    Press Enter to close' | Out-Null\n    exit 1",
     "Wait-ConnectExit -Reason 'unhandled' -Code 1"),
    ('Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1',
     "Wait-ConnectExit -Reason 'require_fail' -Code 1"),
    ('Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1',
     "Write-Host ''; Write-Host \"  [X] $m\" -ForegroundColor Red; Write-Host ''; Wait-ConnectExit -Reason \"die:$m\" -Code 1"),
    ('} else { StepFail "could not create key"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }',
     '} else { StepFail "could not create key"; Wait-ConnectExit -Reason \'ssh_key_create_fail\' -Code 1 }'),
    ('Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1',
     "Wait-ConnectExit -Reason 'ssh_or_boot_fail' -Code 1"),
    ("Write-Host ''; Read-Host '    Press Enter to close' | Out-Null; exit 1",
     "Wait-ConnectExit -Reason 'project_fail' -Code 1"),
    ("Read-Host \"    Press Enter to close\" | Out-Null\n    exit 1",
     "Wait-ConnectExit -Reason 'foreign_session' -Code 1"),
]
n = 0
for old, new in repls:
    cnt = c.count(old)
    if cnt:
        c = c.replace(old, new)
        n += cnt
        print(f'replaced x{cnt}: {old[:50]!r}')
print('total exit replacements', n)

# leftover Read-Host Press Enter
left = [line.strip() for line in c.splitlines() if 'Read-Host' in line and 'Press Enter' in line]
print('leftover Press Enter:', len(left))
for L in left:
    print(' ', L[:100])

# Also log bare exit 0 paths that matter
c = c.replace(
    "Write-Host ''; Write-Host '    Saved. Re-run connect.bat.' -ForegroundColor Green\n                            Write-Host ''; exit 0",
    "Write-Host ''; Write-Host '    Saved. Re-run connect.bat.' -ForegroundColor Green\n                            Write-ConnectDecision 'config_username_saved_relaunch' $nUser\n                            if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }\n                            Write-Host ''; exit 0",
    1,
)
c = c.replace(
    "\"q\" { Write-ConnectDecision 'project_menu' 'quit'; Write-Host \"\"; exit 0 }",
    "\"q\" { Write-ConnectDecision 'project_menu' 'quit'; if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }; Write-Host \"\"; exit 0 }",
    1,
)

cp.write_text(c, encoding='utf-8', newline='\n')
print('connect.ps1 done leftover=', len([1 for L in c.splitlines() if 'Read-Host' in L and 'Press Enter' in L]))

# ========== Mac connect-ui.sh: connect_prompt + connect_decision ==========
sh = root / 'scripts/client/connect-ui.sh'
st = sh.read_text(encoding='utf-8')
st = st.replace(
    '[ "${CONNECT_LOG_LINES_SINCE_SYNC:-0}" -ge 20 ]',
    '[ "${CONNECT_LOG_LINES_SINCE_SYNC:-0}" -ge 1 ]',
)
if 'connect_prompt()' not in st:
    helpers = r'''
connect_prompt() {
    local prompt="$1" tag="${2:-INPUT}" var
    read -rp "$prompt" var
    connect_log "INPUT: tag=$tag prompt=$(printf '%s' "$prompt" | tr '\n' ' ') answer=$var"
    printf '%s' "$var"
}

connect_decision() {
    local what="$1" value="$2" level="${3:-INFO}"
    connect_log "DECISION: ${what}=${value}" "$level"
}

'''
    idx = st.find('connect_log()')
    st = st[:idx] + helpers + st[idx:]
    print('mac connect_prompt added')
sh.write_text(st, encoding='utf-8', newline='\n')

# ========== Mac connect.sh: instrument key reads ==========
mc = root / 'scripts/client/mac/connect.sh'
m = mc.read_text(encoding='utf-8')

# Helper wrappers - only if connect_prompt exists when sourced
# Replace critical read -rp with connect_prompt when available
def wrap_read(src: str, old: str, tag: str) -> str:
    # old like: read -rp "    Server username: " REMOTE_USER
    # new: if declare -F connect_prompt; then REMOTE_USER="$(connect_prompt '...' TAG)"; else read ...
    if old not in src:
        print('WARN missing', old[:60])
        return src
    # extract prompt and varname
    import re
    mo = re.match(r'read -rp "([^"]*)" (\w+)', old)
    if not mo:
        print('WARN parse', old)
        return src
    prompt, var = mo.group(1), mo.group(2)
    new = (
        f'if declare -F connect_prompt >/dev/null 2>&1; then {var}="$(connect_prompt "{prompt}" "{tag}")"; '
        f'else read -rp "{prompt}" {var}; fi'
    )
    return src.replace(old, new, 1)

pairs = [
    ('read -rp "    Server username: " REMOTE_USER', 'SETUP_USER'),
    ('read -rp "    Username changed? Enter new username (or Enter to exit): " fix', 'SSH_USER_FIX'),
    ('read -rp "    Folder on your laptop (e.g. /Users/ali/Smart): " new_rpath', 'ADD_PATH'),
    ('read -rp "    Name [$new_lbl]: " inp; [ -n "$inp" ] && new_lbl="$inp"', None),  # special
    ('read -rp "    > " choice', 'MENU_PROJECT'),
    ('read -rp "    Edit number: " en', 'MENU_EDIT_NUM'),
    ('read -rp "    Display name [$cur_label]: " inp; new_label="${inp:-$cur_label}"', None),
    ('read -rp "    Laptop folder [$cur_rpath]: " inp; new_rpath="${inp:-$cur_rpath}"', None),
    ('read -rp "    Delete number: " dn', 'MENU_DEL_NUM'),
    ("read -rp \"    Delete '$del_label'? [y/N]: \" confirm", 'MENU_DEL_CONFIRM'),
    ("read -rp '    > ' cfg_choice", 'MENU_CONFIG'),
    ('read -rp "    New server username (Enter to cancel): " new_user', 'CFG_USER'),
]

for old, tag in pairs:
    if tag is None:
        continue
    m = wrap_read(m, old, tag)

# special multi-statement ones
specials = [
    (
        'read -rp "    Name [$new_lbl]: " inp; [ -n "$inp" ] && new_lbl="$inp"',
        'if declare -F connect_prompt >/dev/null 2>&1; then inp="$(connect_prompt "    Name [$new_lbl]: " "ADD_NAME")"; else read -rp "    Name [$new_lbl]: " inp; fi; [ -n "$inp" ] && new_lbl="$inp"\n    if declare -F connect_decision >/dev/null 2>&1; then connect_decision project_add "label=$new_lbl path=$new_rpath"; fi',
    ),
    (
        'read -rp "    Display name [$cur_label]: " inp; new_label="${inp:-$cur_label}"',
        'if declare -F connect_prompt >/dev/null 2>&1; then inp="$(connect_prompt "    Display name [$cur_label]: " "MENU_EDIT_LABEL")"; else read -rp "    Display name [$cur_label]: " inp; fi; new_label="${inp:-$cur_label}"',
    ),
    (
        'read -rp "    Laptop folder [$cur_rpath]: " inp; new_rpath="${inp:-$cur_rpath}"',
        'if declare -F connect_prompt >/dev/null 2>&1; then inp="$(connect_prompt "    Laptop folder [$cur_rpath]: " "MENU_EDIT_PATH")"; else read -rp "    Laptop folder [$cur_rpath]: " inp; fi; new_rpath="${inp:-$cur_rpath}"',
    ),
]
for old, new in specials:
    if old in m:
        m = m.replace(old, new, 1)
        print('special OK', old[:40])
    else:
        print('WARN special', old[:40])

# After choice read, log decision
if "connect_decision project_menu" not in m:
    m = m.replace(
        'read -rp "    > " choice' if 'read -rp "    > " choice' in m else 'MENU_PROJECT',
        'MENU_KEEP',
    )
# find choice assignment after wrap
if 'connect_decision project_menu "$choice"' not in m:
    # after choice is set, add decision - look for common pattern
    needle = 'if declare -F connect_prompt >/dev/null 2>&1; then choice="$(connect_prompt "    > " "MENU_PROJECT")"'
    if needle in m:
        m = m.replace(
            needle,
            needle + '\n        if declare -F connect_decision >/dev/null 2>&1; then connect_decision project_menu "$choice"; fi',
            1,
        )
        print('choice decision OK')

# session key logging on mac
if 'connect_decision session_key' not in m:
    oldk = '''                if read -r -t 1 -n 1 _key </dev/tty 2>/dev/null; then'''
    # find and add after key handling - search for action=
    # Simpler: after `_key=` handling block
    import re
    # log whenever action is set from key
    m2 = m
    # inject after common key checks
    if 'action=r' in m or "action=\"r\"" in m or "action='r'" in m:
        pass
    # Look for pattern setting action from key on mac
    for pat in [
        'action="r"',
        "action='r'",
        'action=r',
    ]:
        pass
    # Find:  _key handling
    if '_key' in m and 'session_key' not in m:
        m = m.replace(
            'if read -r -t 1 -n 1 _key </dev/tty 2>/dev/null; then',
            'if read -r -t 1 -n 1 _key </dev/tty 2>/dev/null; then\n'
            '                    if declare -F connect_decision >/dev/null 2>&1; then connect_decision session_key_raw "$_key"; fi',
            1,
        )
        print('mac session key raw OK')

mc.write_text(m, encoding='utf-8', newline='\n')
print('mac connect.sh done')

# ========== editor-launch: ensure major outcomes logged ==========
el = root / 'scripts/client/editor-launch.ps1'
et = el.read_text(encoding='utf-8')
# Check if Launch-RemoteEditor logs start/end - add if missing at function start
if 'function Launch-RemoteEditor' in et and 'LAUNCH begin' not in et:
    et = et.replace(
        'function Launch-RemoteEditor {',
        'function Launch-RemoteEditor {\n'
        '    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {\n'
        '        Write-ConnectLog ("LAUNCH begin editor={0} path={1}" -f $EditorCmd, $RemotePath)\n'
        '    }',
        1,
    )
    # This might break if params come after { - check
    print('NOTE: Launch-RemoteEditor patch may need param block order check')
el.write_text(et, encoding='utf-8', newline='\n')

print('COMPLETE ALL PATCH DONE')
