$ErrorActionPreference='Stop'
$p='D:\Smart\Claude-Code-Server\scripts\client\mac\connect-update.sh'
$raw=[IO.File]::ReadAllText($p)
if($raw -match 'Update retry via'){ Write-Host 'mac already has fallback'; exit 0 }
$old=@'
    target="$(_get_server_target)"
    printf '  Update source: %s\n' "$target"
    remote_ver="$(_ssh_cat "$target" "$REMOTE_BUNDLE/connect-version.txt" | tr -d '\r\n')"
    [ -n "$remote_ver" ] || exit 0
'@
$new=@'
    target="$(_get_server_target)"
    printf '  Update source: %s\n' "$target"
    remote_ver="$(_ssh_cat "$target" "$REMOTE_BUNDLE/connect-version.txt" | tr -d '\r\n')"
    if [ -z "$remote_ver" ]; then
        # Fallback: service account (sepidz/smart) when REMOTE_USER key cannot pull bundle.
        ip="${target##*@}"
        case "$ip" in
            192.168.250.70) svc=sepidz ;;
            *) svc=smart ;;
        esac
        fb="${svc}@${ip}"
        if [ "$fb" != "$target" ]; then
            printf '  Update retry via %s\n' "$fb"
            remote_ver="$(_ssh_cat "$fb" "$REMOTE_BUNDLE/connect-version.txt" | tr -d '\r\n')"
            [ -n "$remote_ver" ] && target="$fb"
        fi
    fi
    [ -n "$remote_ver" ] || exit 0
'@
if($raw.IndexOf($old) -lt 0){ throw 'mac block not found' }
$raw2=$raw.Replace($old,$new)
$raw2=$raw2 -replace "`r`n","`n" -replace "`r","`n"
[IO.File]::WriteAllText($p,$raw2)
Write-Host 'mac connect-update fallback OK'
