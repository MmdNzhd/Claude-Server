from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')
gm = root / 'scripts/client/git-mode.sh'
t = gm.read_text(encoding='utf-8')

# 1) Write Electron machineid file after successful merge
old = '''merge_cursor_auth_into_local_db() {
    local gs="$1" payload="$2" attempt db="${1}/state.vscdb" pairs_file
    [ -n "$payload" ] || return 1
    cursor_sqlite3_available || return 1
    pairs_file="$(mktemp "${TMPDIR:-/tmp}/cursor-auth-pairs.XXXXXX")"
    cursor_auth_payload_to_pairs "$payload" "$pairs_file" || { rm -f "$pairs_file"; return 1; }
    for attempt in 1 2 3 4 5; do
        if cursor_sqlite_merge_pairs "$db" "$pairs_file"; then
            sqlite3 "$db" "PRAGMA wal_checkpoint(FULL);" >/dev/null 2>&1 || true
            rm -f "$pairs_file"
            return 0
        fi
        sleep 0.4
    done
    rm -f "$pairs_file"
    return 1
}'''

new = '''write_cursor_profile_machineid() {
    # Electron reads profile-root machineid; SQLite telemetry alone is not enough.
    local profile mid_file mid=""
    profile="$(get_cursor_remote_profile_dir)"
    mid_file="$profile/machineid"
    [ -d "$profile" ] || mkdir -p "$profile" 2>/dev/null || true
    if [ -n "${1:-}" ]; then
        mid="$(printf '%s' "$1" | tr -d "[:space:]")"
    fi
    if [ -z "$mid" ]; then
        mid="$(sshx "tr -d \"[:space:]\" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null" 2>/dev/null | tr -d "\\r\\n" || true)"
    fi
    [ -n "$mid" ] || return 1
    printf "%s" "$mid" > "$mid_file"
    printf "%s" "$mid" > "$profile/machineId"
    return 0
}

merge_cursor_auth_into_local_db() {
    local gs="$1" payload="$2" attempt db="${1}/state.vscdb" pairs_file mid=""
    [ -n "$payload" ] || return 1
    cursor_sqlite3_available || return 1
    pairs_file="$(mktemp "${TMPDIR:-/tmp}/cursor-auth-pairs.XXXXXX")"
    cursor_auth_payload_to_pairs "$payload" "$pairs_file" || { rm -f "$pairs_file"; return 1; }
    for attempt in 1 2 3 4 5; do
        if cursor_sqlite_merge_pairs "$db" "$pairs_file"; then
            sqlite3 "$db" "PRAGMA wal_checkpoint(FULL);" >/dev/null 2>&1 || true
            mid="$(printf "%s" "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get(\"storage.serviceMachineId\") or d.get(\"telemetry.machineId\") or \"\")" 2>/dev/null || true)"
            write_cursor_profile_machineid "$mid" || true
            rm -f "$pairs_file"
            return 0
        fi
        sleep 0.4
    done
    rm -f "$pairs_file"
    return 1
}'''

if old not in t:
    raise SystemExit('merge_cursor_auth_into_local_db block not found')
t = t.replace(old, new, 1)

# 2) Force refresh when profile machineid file mismatches golden
old_need = '''    if ! cursor_db_value_length "$db" 'storage.serviceMachineId'; then
        reasons="${reasons}serviceMachineId_empty "
    fi
    if declare -F test_personal_cursor_dominant >/dev/null 2>&1 && test_personal_cursor_dominant; then
        reasons="${reasons}personal_without_profile "
    fi'''

new_need = '''    if ! cursor_db_value_length "$db" 'storage.serviceMachineId'; then
        reasons="${reasons}serviceMachineId_empty "
    fi
    # Electron machineid file must match golden (login breaks when it drifts).
    _prof="$(get_cursor_remote_profile_dir)"
    _file_mid=""
    [ -f "$_prof/machineid" ] && _file_mid="$(tr -d "[:space:]" < "$_prof/machineid")"
    _gold_mid="$(sshx "tr -d \\"[:space:]\\" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null" 2>/dev/null | tr -d "\\r\\n" || true)"
    if [ -n "$_gold_mid" ] && [ "$_file_mid" != "$_gold_mid" ]; then
        reasons="${reasons}machineid_file_mismatch "
    fi
    if declare -F test_personal_cursor_dominant >/dev/null 2>&1 && test_personal_cursor_dominant; then
        reasons="${reasons}personal_without_profile "
    fi'''

if old_need not in t:
    raise SystemExit('cursor_auth_needs_refresh needle not found')
t = t.replace(old_need, new_need, 1)

# 3) Harden push_remote_file_if_changed against ~/ double-prefix
old_push = '''    case "$remote" in
        '~/'*) rpath="\$HOME/${remote#~/}" ;;
        '~')   rpath='\$HOME' ;;
        *)     rpath="$remote" ;;
    esac'''
new_push = '''    # Normalize: callers pass ~/path; never allow $HOME/~/path on the server.
    case "$remote" in
        '~/'*) remote="${remote#~/}" ;;
        '~')   remote='' ;;
    esac
    case "$remote" in
        '')                rpath='\$HOME' ;;
        \$HOME/*|'/home/'*) rpath="$remote" ;;
        /*)                rpath="$remote" ;;
        *)                 rpath="\$HOME/$remote" ;;
    esac'''

if old_push not in t:
    raise SystemExit('push_remote needle not found')
t = t.replace(old_push, new_push, 1)

# scp still needs ~/ form for OpenSSH expand - fix scp line to use ~/ when relative
old_scp = '''    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$src" "$ALIAS:$remote" 2>/dev/null || return 1
    case "$remote" in
        */laptop-exec|*/laptop-exec-setup|*/laptop-exec-guard.sh)
            sshx "chmod +x $rpath" >/dev/null 2>&1 || true ;;
    esac'''
new_scp = '''    local scp_dest="$remote"
    case "$scp_dest" in
        ''|\$HOME) scp_dest='~' ;;
        \$HOME/*)  scp_dest="~/${scp_dest#\$HOME/}" ;;
        /*)        ;;
        *)         scp_dest="~/$scp_dest" ;;
    esac
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$src" "$ALIAS:$scp_dest" 2>/dev/null || return 1
    case "$scp_dest" in
        */laptop-exec|*/laptop-exec-setup|*/laptop-exec-guard.sh)
            sshx "chmod +x $rpath" >/dev/null 2>&1 || true ;;
    esac'''

if old_scp not in t:
    raise SystemExit('scp needle not found')
t = t.replace(old_scp, new_scp, 1)

gm.write_bytes(t.replace('\r\n','\n').replace('\r','\n').encode())
print('OK git-mode.sh')

# Windows: write machineid into profile root
ps = root / 'scripts/client/cursor-auth-laptop.ps1'
pt = ps.read_text(encoding='utf-8')
if 'Write-CursorProfileMachineId' not in pt:
    # find a good insertion after Merge-CursorAuthIntoLocalDb success paths
    needle = 'function Get-CursorRemoteProfileDir'
    # simpler: add helper and call from Merge after successful upsert
    # Search for machine-id.txt download / apply
    if 'machine-id.txt' in pt and 'machineid' not in pt.lower().replace('machine-id',''):
        pass
    # Find Sync-CursorGoldenAuth or Merge function end
    m = re.search(r'(function Merge-CursorAuthIntoLocalDb[\s\S]*?\n\})', pt)
    print('has Merge-CursorAuthIntoLocalDb', bool(m))
    
# Add Windows machineid write near existing machineId handling
win_needle = None
for i, line in enumerate(pt.splitlines()):
    if 'storage.serviceMachineId' in line and 'machineId' in line.lower():
        print(f'win line {i+1}: {line.strip()[:100]}')

# Patch Windows: after successful merge in Sync-CursorGoldenAuth / Apply
# Look for writing golden-synced-at
if "golden-synced-at" in pt or 'GoldenSyncedAt' in pt or 'golden-synced-at.txt' in pt:
    print('windows has golden-synced-at marker')
else:
    print('windows no golden-synced-at string - searching Sync')

# Read relevant section of ps1 around line 400-500
lines = pt.splitlines()
for i in range(380, 520):
    if i < len(lines):
        if any(x in lines[i] for x in ['machine-id', 'Merge-Cursor', 'Synced', 'ProfileDir', 'serviceMachineId']):
            print(f'{i+1}:{lines[i]}')

print('done scan')
