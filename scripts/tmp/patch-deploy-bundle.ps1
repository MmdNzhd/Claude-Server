$ErrorActionPreference = 'Stop'
$path = 'D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-client-bundle.sh'
$raw = [IO.File]::ReadAllText($path)

$marker = 'chmod 755 "$BUNDLE_ROOT" "$BUNDLE_ROOT/mac" "$BUNDLE_ROOT/server"'
if ($raw.IndexOf($marker) -lt 0) { throw 'marker not found' }
if ($raw.Contains('Sync laptop SSH keys into sepidz')) {
    Write-Host 'already has key sync'
    exit 0
}

$insert = @'

# Old Windows packages hardcode sepidz@IP for auto-update. Merge every
# /home/*/authorized_keys into sepidz so clients (farzadb, ...) can pull the
# world-readable bundle without the deploy key. Idempotent; keeps existing keys.
_sync_sepidz_update_keys() {
    local ak="/home/sepidz/.ssh/authorized_keys"
    local tmp before after
    [ -d /home/sepidz/.ssh ] || return 0
    tmp="$(mktemp)"
    [ -f "$ak" ] && cat "$ak" >"$tmp" || : >"$tmp"
    before="$(wc -l <"$tmp" | tr -d " ")"
    for d in /home/*; do
        u="$(basename "$d")"
        case "$u" in sepidz|root) continue ;; esac
        [ -f "$d/.ssh/authorized_keys" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                ''|\#*) continue ;;
                ssh-*|ecdsa-*|sk-*) ;;
                *) continue ;;
            esac
            # Match on key material (field 2) to avoid dup comments.
            key="$(printf '%s\n' "$line" | awk '{print $2}')"
            [ -n "$key" ] || continue
            if ! awk -v k="$key" '$2==k {found=1} END{exit !found}' "$tmp" 2>/dev/null; then
                printf '%s\n' "$line" >>"$tmp"
            fi
        done <"$d/.ssh/authorized_keys"
    done
    install -o sepidz -g sepidz -m 600 "$tmp" "$ak"
    after="$(wc -l <"$ak" | tr -d " ")"
    rm -f "$tmp"
    ok "sepidz update keys: $before -> $after"
}
_sync_sepidz_update_keys

'@

# Insert before the chmod 755 BUNDLE_ROOT line near the end
$idx = $raw.LastIndexOf($marker)
$raw2 = $raw.Substring(0, $idx) + $insert + $raw.Substring($idx)
# Normalize to LF
$raw2 = $raw2 -replace "`r`n", "`n" -replace "`r", "`n"
[IO.File]::WriteAllText($path, $raw2)
Write-Host 'deploy-client-bundle.sh patched'
