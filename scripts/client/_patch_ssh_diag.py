from pathlib import Path
root = Path(__file__).resolve().parents[2]
gm = root / "scripts/client/git-mode.sh"
g = gm.read_text(encoding="utf-8")

diag = r'''diagnose_laptop_ssh_failure() {
    # Write actionable diagnostics to connect.log + a short on-screen summary.
    local pub="${1:-}" user frag="" key_tmp="" ssh_out="" ak="$HOME/.ssh/authorized_keys"
    local port22=0 rl=0 in_group="?" key_in_ak=0 from_line="?" home_mode="" ssh_mode="" ak_mode=""
    local log_path="${CONNECT_LOG_PATH:-$HOME/.config/claude-connect/logs/connect.log}"
    user="${LAPTOP_USER:-$(whoami)}"
    pub="${pub//$'\r'/}"
    frag="$(printf '%s' "$pub" | awk '{print $2}')"

    _dlog() {
        local m="$1"
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LAPTOP_SSH_DIAG: $m" 'WARN'
        fi
        printf '      diag: %s\n' "$m"
    }

    _dlog "begin short_user=$user realname=$(mac_login_realname 2>/dev/null || true) server_user=${REMOTE_USER:-?} os=$(uname -s)"
    nc -zw1 127.0.0.1 22 2>/dev/null && port22=1 || port22=0
    remote_login_on && rl=1 || rl=0
    _dlog "port22_open=$port22 remote_login_on=$rl"

    if dseditgroup -o check -n . -m "$user" com.apple.access_ssh >/dev/null 2>&1; then
        in_group=yes
    else
        # group may not exist when "All users" allowed
        if dseditgroup -o read com.apple.access_ssh >/dev/null 2>&1; then
            in_group=no
        else
            in_group=absent_or_all_users
        fi
    fi
    _dlog "access_ssh_group=$in_group (no/absent often OK if Sharing allows All users)"

    home_mode="$(stat -f '%Lp' "$HOME" 2>/dev/null || true)"
    ssh_mode="$(stat -f '%Lp' "$HOME/.ssh" 2>/dev/null || true)"
    ak_mode="$(stat -f '%Lp' "$ak" 2>/dev/null || true)"
    _dlog "perms home=$home_mode .ssh=$ssh_mode authorized_keys=$ak_mode"

    if [ -n "$frag" ] && [ -f "$ak" ] && grep -Fq "$frag" "$ak" 2>/dev/null; then
        key_in_ak=1
        from_line="$(grep -F "$frag" "$ak" | head -1 | awk '{print $1}')"
    fi
    _dlog "server_pubkey_in_authorized_keys=$key_in_ak from_prefix=$from_line"

    if [ -z "$frag" ]; then
        _dlog "FAIL reason=no_server_pubkey_fragment"
    elif [ "$key_in_ak" -eq 0 ]; then
        _dlog "FAIL reason=pubkey_not_in_authorized_keys"
    elif [ "$port22" -eq 0 ]; then
        _dlog "FAIL reason=sshd_not_listening_on_22"
    else
        key_tmp="$(mktemp "${TMPDIR:-/tmp}/claude-laptop-diag.XXXXXX")"
        umask 077
        if sshx "cat \$HOME/.ssh/claude_laptop" 2>/dev/null > "$key_tmp"; then
            chmod 600 "$key_tmp"
            ssh_out="$(ssh -vv -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
                -o IdentitiesOnly=yes -i "$key_tmp" "${user}@127.0.0.1" true 2>&1 | tail -40)"
            _dlog "local_ssh_exit=$? (ssh -vv last lines follow)"
            printf '%s\n' "$ssh_out" | while IFS= read -r line; do
                [ -n "$line" ] || continue
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "LAPTOP_SSH_DIAG_SSH: $line" 'DEBUG'
                fi
            done
            # On-screen: only high-signal lines
            printf '%s\n' "$ssh_out" | grep -Ei 'Permission denied|Authentications that can continue|publickey|Offering public key|Server accepts key|Authentication succeeded|Connection refused|Connection reset|Too many|disabled|not allowed|User .* from' | tail -12 | while IFS= read -r line; do
                printf '      ssh: %s\n' "$line"
            done
        else
            _dlog "FAIL reason=could_not_fetch_server_private_key_via_sshx"
        fi
        rm -f "$key_tmp"
    fi

    _dlog "log_file=${CONNECT_LOG_PATH:-$log_path}"
    warn "Full SSH diagnostics: ${CONNECT_LOG_PATH:-$log_path}"
    return 0
}

'''

if "diagnose_laptop_ssh_failure()" in g:
    raise SystemExit('already present')

# Insert before verify_laptop_local_pubkey
anchor = "verify_laptop_local_pubkey() {"
if anchor not in g:
    raise SystemExit('verify anchor missing')
g = g.replace(anchor, diag + anchor, 1)

# Enhance verify to log failure reason lightly when connect_log exists
old_v = '''verify_laptop_local_pubkey() {
    local pub="$1" frag="" key_tmp="" rc=1
    pub="${pub//$\'\\r\'/}"
    frag="$(printf '%s' "$pub" | awk '{print $2}')"
    [ -n "$frag" ] || return 1
    grep -Fq "$frag" "$HOME/.ssh/authorized_keys" 2>/dev/null || return 1
    key_tmp="$(mktemp "${TMPDIR:-/tmp}/claude-laptop-key.XXXXXX")"
    umask 077
    if sshx "cat \\$HOME/.ssh/claude_laptop" 2>/dev/null > "$key_tmp"; then
        chmod 600 "$key_tmp"
        ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \\
            -i "$key_tmp" "${LAPTOP_USER:-$(whoami)}@127.0.0.1" true >/dev/null 2>&1
        rc=$?
    fi
    rm -f "$key_tmp"
    [ "$rc" -eq 0 ]
}'''

# Simpler: just call diagnose at end of invoke before return 1
old_end = '''    warn "Laptop SSH still not accepting the server key."
    warn "SSH uses Mac short name '${user}' (whoami). Server user is '${REMOTE_USER:-?}' (different)."
    _rn="$(mac_login_realname 2>/dev/null || true)"
    if [ -n "${_rn}" ] && [ "${_rn}" != "${user}" ]; then
        warn "In System Settings the name may look like '${_rn}' — allow THAT row (or All users)."
    else
        warn "System Settings -> Sharing -> Remote Login: ON, allow '${user}' or All users."
    fi
    unset LAPTOP_ADMIN_PW
    return 1
}'''

new_end = '''    warn "Laptop SSH still not accepting the server key."
    warn "SSH uses Mac short name '${user}' (whoami). Server user is '${REMOTE_USER:-?}' (different)."
    _rn="$(mac_login_realname 2>/dev/null || true)"
    if [ -n "${_rn}" ] && [ "${_rn}" != "${user}" ]; then
        warn "In System Settings the name may look like '${_rn}' — allow THAT row (or All users)."
    else
        warn "System Settings -> Sharing -> Remote Login: ON, allow '${user}' or All users."
    fi
    diagnose_laptop_ssh_failure "$pub" || true
    unset LAPTOP_ADMIN_PW
    return 1
}'''

if old_end not in g:
    raise SystemExit('invoke end missing')
g = g.replace(old_end, new_end, 1)

# Also diagnose when ensure fails after invoke
old_ens = '''ensure_laptop_ssh_key() {
    local pub=""
    pub="$(fetch_laptop_server_pubkey "${1:-}")" || return 1
    install_laptop_server_pubkey "$pub" || return 1
    verify_laptop_local_pubkey "$pub" && return 0
    warn "Server cannot SSH back to this Mac yet - fixing (password at most once)..."
    invoke_laptop_admin_ops "$pub" || return 1
    verify_laptop_local_pubkey "$pub"
}'''
new_ens = '''ensure_laptop_ssh_key() {
    local pub=""
    pub="$(fetch_laptop_server_pubkey "${1:-}")" || return 1
    install_laptop_server_pubkey "$pub" || return 1
    verify_laptop_local_pubkey "$pub" && return 0
    warn "Server cannot SSH back to this Mac yet - fixing (password at most once)..."
    if ! invoke_laptop_admin_ops "$pub"; then
        # diagnose already run inside invoke on failure
        return 1
    fi
    verify_laptop_local_pubkey "$pub" && return 0
    diagnose_laptop_ssh_failure "$pub" || true
    return 1
}'''
if old_ens not in g:
    raise SystemExit('ensure missing')
g = g.replace(old_ens, new_ens, 1)

gm.write_text(g, encoding="utf-8", newline="\n")

# bump version
for rel in [
    "scripts/client/mac/connect.sh",
    "scripts/client/windows/connect.ps1",
    "scripts/client/mac/connect-version.txt",
    "scripts/client/windows/connect-version.txt",
]:
    p = root / rel
    t = p.read_text(encoding="utf-8")
    for a in ("20260717.18", "20260717.17", "20260717.16"):
        if a in t:
            t = t.replace(a, "20260717.19")
            break
    if "20260717.19" not in t:
        raise SystemExit(rel)
    p.write_text(t, encoding="utf-8", newline="\n")

print("ok")
