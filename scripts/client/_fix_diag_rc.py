from pathlib import Path
p = Path(__file__).resolve().parents[2] / "scripts/client/git-mode.sh"
t = p.read_text(encoding="utf-8")
old = '''        if sshx "cat \\$HOME/.ssh/claude_laptop" 2>/dev/null > "$key_tmp"; then
            chmod 600 "$key_tmp"
            ssh_out="$(ssh -vv -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \\
                -o IdentitiesOnly=yes -i "$key_tmp" "${user}@127.0.0.1" true 2>&1 | tail -40)"
            _dlog "local_ssh_exit=$? (ssh -vv last lines follow)"
            printf '%s\\n' "$ssh_out" | while IFS= read -r line; do
                [ -n "$line" ] || continue
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "LAPTOP_SSH_DIAG_SSH: $line" 'DEBUG'
                fi
            done
            # On-screen: only high-signal lines
            printf '%s\\n' "$ssh_out" | grep -Ei 'Permission denied|Authentications that can continue|publickey|Offering public key|Server accepts key|Authentication succeeded|Connection refused|Connection reset|Too many|disabled|not allowed|User .* from' | tail -12 | while IFS= read -r line; do
                printf '      ssh: %s\\n' "$line"
            done
        else
            _dlog "FAIL reason=could_not_fetch_server_private_key_via_sshx"
        fi
        rm -f "$key_tmp"'''
new = '''        if sshx "cat \\$HOME/.ssh/claude_laptop" 2>/dev/null > "$key_tmp"; then
            chmod 600 "$key_tmp"
            _ssh_err="$(mktemp "${TMPDIR:-/tmp}/claude-ssh-diag.XXXXXX")"
            ssh -vv -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \\
                -o IdentitiesOnly=yes -i "$key_tmp" "${user}@127.0.0.1" true >"$_ssh_err" 2>&1
            _ssh_rc=$?
            ssh_out="$(tail -60 "$_ssh_err" 2>/dev/null || true)"
            rm -f "$_ssh_err"
            _dlog "local_ssh_exit=${_ssh_rc} (ssh -vv last lines in log)"
            printf '%s\\n' "$ssh_out" | while IFS= read -r line; do
                [ -n "$line" ] || continue
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "LAPTOP_SSH_DIAG_SSH: $line" 'DEBUG'
                fi
            done
            printf '%s\\n' "$ssh_out" | grep -Ei 'Permission denied|Authentications that can continue|publickey|Offering public key|Server accepts key|Authentication succeeded|Connection refused|Connection reset|Too many|disabled|not allowed|User .* from' | tail -12 | while IFS= read -r line; do
                printf '      ssh: %s\\n' "$line"
            done
            case "${_ssh_rc}" in
                0) _dlog "unexpected: ssh succeeded during diagnose" ;;
                255) _dlog "HINT: connection/auth failed — often Remote Login allow-list or key rejected" ;;
                *) _dlog "HINT: ssh exit ${_ssh_rc}" ;;
            esac
        else
            _dlog "FAIL reason=could_not_fetch_server_private_key_via_sshx"
        fi
        rm -f "$key_tmp"'''
# file has single backslash for $HOME in sshx already
old = old.replace('\\\\$HOME', '\\$HOME')
new = new.replace('\\\\$HOME', '\\$HOME')
if old not in t:
    # try reading exact snippet from file
    idx = t.find('local_ssh_exit=$?')
    print('idx', idx)
    print(repr(t[idx-200:idx+200]))
    raise SystemExit('snippet missing')
p.write_text(t.replace(old, new, 1), encoding="utf-8", newline="\n")
print('fixed rc')
