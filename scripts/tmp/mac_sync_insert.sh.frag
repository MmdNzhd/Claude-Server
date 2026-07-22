    # --- LOG_SYNC_RECONCILE (parity with Windows): pending + size verify + tail hash ---
    pending_file="${CONNECT_LOG_PATH}.sync-pending"
    remote_before=0
    if [ -f "$pending_file" ]; then
        IFS='|' read -r pend_off pend_take pend_r0 < "$pending_file" || true
        if [ "$pend_off" = "$off" ] && [ "$pend_take" = "$take" ]; then
            r_now=0
            if declare -F sshx >/dev/null 2>&1; then
                r_now="$(sshx "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            else
                r_now="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            fi
            : "${r_now:=0}"
            need=$((pend_r0 + pend_take))
            if [ "$r_now" -ge "$need" ] 2>/dev/null; then
                CONNECT_LOG_SYNC_OFF=$((off + take))
                printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
                rm -f "$pending_file" "${CONNECT_LOG_PATH}.chunk"
                flock -u 8 2>/dev/null || true
                return 0
            fi
        fi
    fi
    local_hash="$(sha256sum "${CONNECT_LOG_PATH}.chunk" 2>/dev/null | awk '{print $1}')"
    if [ -n "$local_hash" ]; then
        if declare -F sshx >/dev/null 2>&1; then
            remote_hash="$(sshx "f=\"\$HOME/${remote_day}\"; [ -f \"\$f\" ] || { echo none; exit 0; }; sz=\$(stat -c%s \"\$f\" 2>/dev/null || echo 0); [ \"\$sz\" -ge ${take} ] || { echo short; exit 0; }; tail -c ${take} \"\$f\" | sha256sum | awk '{print \$1}'" 2>/dev/null | tr -dc 'a-f0-9')"
        else
            remote_hash="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$ALIAS" "f=\"\$HOME/${remote_day}\"; [ -f \"\$f\" ] || { echo none; exit 0; }; sz=\$(stat -c%s \"\$f\" 2>/dev/null || echo 0); [ \"\$sz\" -ge ${take} ] || { echo short; exit 0; }; tail -c ${take} \"\$f\" | sha256sum | awk '{print \$1}'" 2>/dev/null | tr -dc 'a-f0-9')"
        fi
        if [ -n "$remote_hash" ] && [ "$remote_hash" = "$local_hash" ]; then
            CONNECT_LOG_SYNC_OFF=$((off + take))
            printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
            rm -f "$pending_file" "${CONNECT_LOG_PATH}.chunk"
            flock -u 8 2>/dev/null || true
            return 0
        fi
    fi
    if declare -F sshx >/dev/null 2>&1; then
        remote_before="$(sshx "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    else
        remote_before="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    fi
    : "${remote_before:=0}"
    printf '%s|%s|%s' "$off" "$take" "$remote_before" > "$pending_file" 2>/dev/null || true

