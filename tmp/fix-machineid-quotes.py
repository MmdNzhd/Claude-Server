from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
gm = root / 'scripts/client/git-mode.sh'
t = gm.read_text(encoding='utf-8')

# Fix write_cursor_profile_machineid + merge mid extract
old = '''write_cursor_profile_machineid() {
    # Electron reads profile-root machineid; SQLite telemetry alone is not enough.
    local profile mid_file mid=""
    profile="$(get_cursor_remote_profile_dir)"
    mid_file="$profile/machineid"
    [ -d "$profile" ] || mkdir -p "$profile" 2>/dev/null || true
    if [ -n "${1:-}" ]; then
        mid="$(printf '%s' "$1" | tr -d "[:space:]")"
    fi
    if [ -z "$mid" ]; then
        mid="$(sshx "tr -d "[:space:]" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null" 2>/dev/null | tr -d "\\r\\n" || true)"
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
            mid="$(printf "%s" "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get("storage.serviceMachineId") or d.get("telemetry.machineId") or "")" 2>/dev/null || true)"
            write_cursor_profile_machineid "$mid" || true
            rm -f "$pairs_file"
            return 0
        fi
        sleep 0.4
    done
    rm -f "$pairs_file"
    return 1
}'''

# Read actual broken block from file by markers
start = t.find('write_cursor_profile_machineid() {')
end = t.find('merge_cursor_storage_json_from_golden() {')
if start < 0 or end < 0:
    raise SystemExit(f'markers missing start={start} end={end}')

new_block = r'''write_cursor_profile_machineid() {
    # Electron reads profile-root machineid; SQLite telemetry alone is not enough.
    local profile mid_file mid=""
    profile="$(get_cursor_remote_profile_dir)"
    mid_file="$profile/machineid"
    [ -d "$profile" ] || mkdir -p "$profile" 2>/dev/null || true
    if [ -n "${1:-}" ]; then
        mid="$(printf '%s' "$1" | tr -d '[:space:]')"
    fi
    if [ -z "$mid" ]; then
        mid="$(sshx 'tr -d "[:space:]" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null' 2>/dev/null | tr -d '\r\n' || true)"
    fi
    [ -n "$mid" ] || return 1
    printf '%s' "$mid" > "$mid_file"
    printf '%s' "$mid" > "$profile/machineId"
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
            if command -v jq >/dev/null 2>&1; then
                mid="$(printf '%s' "$payload" | jq -r '."storage.serviceMachineId" // ."telemetry.machineId" // empty' 2>/dev/null || true)"
            else
                mid="$(awk -F'\t' '$1=="storage.serviceMachineId"{print $2; exit}' "$pairs_file" 2>/dev/null || true)"
                [ -n "$mid" ] || mid="$(awk -F'\t' '$1=="telemetry.machineId"{print $2; exit}' "$pairs_file" 2>/dev/null || true)"
            fi
            write_cursor_profile_machineid "$mid" || true
            rm -f "$pairs_file"
            return 0
        fi
        sleep 0.4
    done
    rm -f "$pairs_file"
    return 1
}

'''

t = t[:start] + new_block + t[end:]

# Fix push_remote case patterns for $HOME
old_case = '''    case "$remote" in
        '')                rpath='\$HOME' ;;
        \$HOME/*|'/home/'*) rpath="$remote" ;;
        /*)                rpath="$remote" ;;
        *)                 rpath="\$HOME/$remote" ;;
    esac'''
new_case = '''    case "$remote" in
        '')          rpath='\$HOME' ;;
        '$HOME/'*)   rpath="$remote" ;;
        /home/*)     rpath="$remote" ;;
        /*)          rpath="$remote" ;;
        *)           rpath="\$HOME/$remote" ;;
    esac'''
if old_case not in t:
    raise SystemExit('case block missing')
t = t.replace(old_case, new_case, 1)

old_scp = '''    case "$scp_dest" in
        ''|\$HOME) scp_dest='~' ;;
        \$HOME/*)  scp_dest="~/${scp_dest#\$HOME/}" ;;
        /*)        ;;
        *)         scp_dest="~/$scp_dest" ;;
    esac'''
new_scp = '''    case "$scp_dest" in
        ''|'$HOME') scp_dest='~' ;;
        '$HOME/'*)  scp_dest="~/${scp_dest#\$HOME/}" ;;
        /*)         ;;
        *)          scp_dest="~/$scp_dest" ;;
    esac'''
if old_scp not in t:
    raise SystemExit('scp case missing')
t = t.replace(old_scp, new_scp, 1)

# Fix machineid_file_mismatch gold mid fetch quotes if broken
# Read that section
idx = t.find('machineid_file_mismatch')
print('mismatch context:', repr(t[idx-400:idx+80]))

gm.write_bytes(t.replace('\r\n','\n').replace('\r','\n').encode())
print('OK quotes fixed')

# Windows machineid write
ps = root / 'scripts/client/cursor-auth-laptop.ps1'
pt = ps.read_text(encoding='utf-8')
if 'Write-CursorProfileMachineId' not in pt:
    helper = '''
function Write-CursorProfileMachineId {
    param([string]$MachineId)
    if (-not $MachineId) { return $false }
    $profileDir = Get-CursorRemoteProfileDir
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    $mid = $MachineId.Trim()
    Set-Content -LiteralPath (Join-Path $profileDir 'machineid') -Value $mid -Encoding Ascii -NoNewline
    Set-Content -LiteralPath (Join-Path $profileDir 'machineId') -Value $mid -Encoding Ascii -NoNewline
    return $true
}

'''
    # insert before Merge-CursorAuthIntoLocalDb
    pt = pt.replace('function Merge-CursorAuthIntoLocalDb {', helper + 'function Merge-CursorAuthIntoLocalDb {', 1)
    # after successful merge return true - expand Merge to write machineid
    old_m = '''    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        if ([CursorAuthSqlite]::MergeAuthValues($DbPath, $map)) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return $false
}'''
    new_m = '''    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        if ([CursorAuthSqlite]::MergeAuthValues($DbPath, $map)) {
            $mid = $null
            if ($map.ContainsKey('storage.serviceMachineId')) { $mid = $map['storage.serviceMachineId'] }
            elseif ($map.ContainsKey('telemetry.machineId')) { $mid = $map['telemetry.machineId'] }
            if ($mid) { Write-CursorProfileMachineId -MachineId $mid | Out-Null }
            return $true
        }
        Start-Sleep -Milliseconds 400
    }
    return $false
}'''
    if old_m not in pt:
        raise SystemExit('windows merge loop missing')
    pt = pt.replace(old_m, new_m, 1)
    ps.write_text(pt, encoding='utf-8', newline='\n')
    print('OK windows machineid')
else:
    print('SKIP windows already has helper')

# bump .29
for rel in [
    'scripts/client/mac/connect.sh',
    'scripts/client/windows/connect.ps1',
    'scripts/client/mac/connect-version.txt',
    'scripts/client/windows/connect-version.txt',
    'publish/README.txt',
    'publish/README-sepidz.txt',
    'CLAUDE.md',
]:
    p = root / rel
    if not p.exists():
        continue
    c = p.read_text(encoding='utf-8')
    c2 = c.replace('20260717.28', '20260717.29').replace('20260717.27', '20260717.29')
    if c2 != c:
        if p.suffix == '.sh' or 'mac/connect' in rel.replace('\\\\','/'):
            p.write_bytes(c2.replace('\\r\\n','\\n').replace('\\r','\\n').encode())
        else:
            p.write_text(c2, encoding='utf-8')
        print('bumped', rel)

# ensure connect.sh LF
p = root / 'scripts/client/mac/connect.sh'
p.write_bytes(p.read_bytes().replace(b'\\r\\n', b'\\n').replace(b'\\r', b'\\n'))
print('done')
