$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

function Set-LfText([string]$Path, [string]$Text) {
    $Text = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    [IO.File]::WriteAllText($Path, $Text)
}

# --- 1) Shared key-sync snippet ---
$syncFn = @'

# Merge /home/*/authorized_keys into sepidz so old Windows packages that
# hardcode sepidz@IP can still pull the world-readable client bundle.
_sync_sepidz_update_keys() {
    local ak="/home/sepidz/.ssh/authorized_keys"
    local tmp before after
    [ -d /home/sepidz/.ssh ] || return 0
    tmp="$(mktemp)"
    [ -f "$ak" ] && cat "$ak" >"$tmp" || : >"$tmp"
    before="$(wc -l <"$tmp" | tr -d ' ')"
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
            key="$(printf '%s\n' "$line" | awk '{print $2}')"
            [ -n "$key" ] || continue
            if ! awk -v k="$key" '$2==k {found=1} END{exit !found}' "$tmp" 2>/dev/null; then
                printf '%s\n' "$line" >>"$tmp"
            fi
        done <"$d/.ssh/authorized_keys"
    done
    install -o sepidz -g sepidz -m 600 "$tmp" "$ak"
    after="$(wc -l <"$ak" | tr -d ' ')"
    rm -f "$tmp"
    ok "sepidz update keys: $before -> $after"
}

'@

# --- 2) install-client-bundle.sh ---
$ib = Join-Path $root 'scripts\server\commands\install-client-bundle.sh'
$ibRaw = [IO.File]::ReadAllText($ib)
if ($ibRaw -notmatch '_sync_sepidz_update_keys') {
    $done = 'VER="$(tr -d ''\r\n'' < "$BUNDLE_ROOT/connect-version.txt")"'
    # find unique insertion before Done echo
    $needle = "VER=`"`$(tr -d '\r\n' < `"`$BUNDLE_ROOT/connect-version.txt`")`""
    # simpler: insert before final Done block
    $marker = "echo -e `"`${GREEN}Done.`${NC} Client bundle v`${VER} at `$BUNDLE_ROOT`""
    if ($ibRaw.IndexOf('echo -e "${GREEN}Done.${NC} Client bundle v${VER} at $BUNDLE_ROOT"') -lt 0) {
        throw 'install-client-bundle Done marker missing'
    }
    $ibRaw = $ibRaw.Replace(
        'VER="$(tr -d ''\r\n'' < "$BUNDLE_ROOT/connect-version.txt")"',
        "VER=`"`$(tr -d '\r\n' < `"`$BUNDLE_ROOT/connect-version.txt`")`"`n$($syncFn.Trim())`n_sync_sepidz_update_keys"
    )
    # The above might fail due to quoting - use index approach
}
# Always rewrite via index for reliability
$ibRaw = [IO.File]::ReadAllText($ib)
if ($ibRaw -notmatch '_sync_sepidz_update_keys') {
    $insAt = $ibRaw.LastIndexOf('VER="$(tr -d')
    if ($insAt -lt 0) { throw 'VER line not found in install-client-bundle' }
    # insert sync after VER= line
    $nl = $ibRaw.IndexOf("`n", $insAt)
    if ($nl -lt 0) { throw 'newline after VER not found' }
    $ibRaw = $ibRaw.Substring(0, $nl + 1) + $syncFn + "`n_sync_sepidz_update_keys`n" + $ibRaw.Substring($nl + 1)
    Set-LfText $ib $ibRaw
    Write-Host 'install-client-bundle: key sync added'
} else {
    Write-Host 'install-client-bundle: already has key sync'
}

# --- 3) add-user.sh: timeout + append key to sepidz ---
$au = Join-Path $root 'scripts\server\commands\add-user.sh'
$auRaw = [IO.File]::ReadAllText($au)
$oldHook = @'
        "$HOME/.local/bin/claude-automount" 2>/dev/null || /usr/local/bin/claude-automount 2>/dev/null
'@
$newHook = @'
        timeout 10 "$HOME/.local/bin/claude-automount" 2>/dev/null || timeout 10 /usr/local/bin/claude-automount 2>/dev/null
'@
if ($auRaw.Contains($oldHook)) {
    $auRaw = $auRaw.Replace($oldHook, $newHook)
    Write-Host 'add-user: bashrc timeout patched'
} elseif ($auRaw -match 'timeout 10.*claude-automount') {
    Write-Host 'add-user: bashrc timeout already present'
} else {
    Write-Host 'WARN: add-user automount hook pattern not found'
}

$auAppend = @'

# Allow this user's laptop key to pull client auto-update via sepidz@ (legacy packages).
if [ -f "/home/$USERNAME/.ssh/authorized_keys" ] && [ -d /home/sepidz/.ssh ]; then
    ak=/home/sepidz/.ssh/authorized_keys
    tmp=$(mktemp)
    [ -f "$ak" ] && cat "$ak" >"$tmp" || : >"$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|\#*) continue ;; ssh-*|ecdsa-*|sk-*) ;; *) continue ;; esac
        key=$(printf '%s\n' "$line" | awk '{print $2}')
        [ -n "$key" ] || continue
        if ! awk -v k="$key" '$2==k {found=1} END{exit !found}' "$tmp" 2>/dev/null; then
            printf '%s\n' "$line" >>"$tmp"
        fi
    done <"/home/$USERNAME/.ssh/authorized_keys"
    install -o sepidz -g sepidz -m 600 "$tmp" "$ak"
    rm -f "$tmp"
    ok "sepidz update keys refreshed for $USERNAME"
fi

'@
if ($auRaw -notmatch 'sepidz update keys refreshed') {
    $doneIdx = $auRaw.LastIndexOf('echo -e "${GREEN}${BOLD}Done.${NC}')
    if ($doneIdx -lt 0) { throw 'add-user Done marker missing' }
    $auRaw = $auRaw.Substring(0, $doneIdx) + $auAppend + $auRaw.Substring($doneIdx)
    Write-Host 'add-user: sepidz key sync on create'
}
Set-LfText $au $auRaw

# --- 4) connect-update.ps1: try REMOTE_USER then service account ---
$cu = Join-Path $root 'scripts\client\windows\connect-update.ps1'
$cuRaw = [IO.File]::ReadAllText($cu)
if ($cuRaw -notmatch 'Resolve-UpdateEndpoint') {
    $oldMain = @'
$ep = Get-ServerEndpoint
Write-UpdateMsg ("Update source: {0}" -f $ep.Display) 'DarkGray'
$remoteVer = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/connect-version.txt"
if (-not $remoteVer) {
    Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) 'DarkYellow'
    exit 0
}
'@
    $newMain = @'
function Get-FallbackServiceUser {
    param([string]$Ip)
    if ($Ip -eq '192.168.250.70') { return 'sepidz' }
    if ($Ip -eq '192.168.210.240') { return 'smart' }
    return 'smart'
}

function Resolve-UpdateEndpoint {
    # Try laptop REMOTE_USER first, then sepidz/smart service account.
    $primary = Get-ServerEndpoint
    $ver = Invoke-SshCat -Target $primary.Target -RemotePath "$RemoteBundle/connect-version.txt"
    if ($ver) {
        return @{ Target = $primary.Target; Display = $primary.Display; RemoteVer = $ver }
    }
    $ip = Get-LocalServerIp
    if (-not $ip) { return $null }
    $svc = Get-FallbackServiceUser -Ip $ip
    $user = Get-RemoteUserFromConf
    if ($user -and ($user -ne $svc)) {
        $fb = "{0}@{1}" -f $svc, $ip
        Write-UpdateMsg ("Update retry via {0}" -f $fb) 'DarkGray'
        $ver2 = Invoke-SshCat -Target $fb -RemotePath "$RemoteBundle/connect-version.txt"
        if ($ver2) {
            return @{ Target = $fb; Display = $fb; RemoteVer = $ver2 }
        }
    } elseif (-not $user) {
        # primary already used service account
    } else {
        # primary was service; try nothing else
    }
    return $null
}

$resolved = Resolve-UpdateEndpoint
if (-not $resolved) {
    $ep = Get-ServerEndpoint
    Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) 'DarkYellow'
    exit 0
}
$ep = @{ Target = $resolved.Target; Display = $resolved.Display }
$remoteVer = $resolved.RemoteVer
Write-UpdateMsg ("Update source: {0}" -f $ep.Display) 'DarkGray'
'@
    if ($cuRaw.IndexOf($oldMain) -lt 0) {
        # fuzzy: find by unique lines
        $s = $cuRaw.IndexOf('$ep = Get-ServerEndpoint')
        if ($s -lt 0) { throw 'connect-update main ep block start missing' }
        $e = $cuRaw.IndexOf('if (-not (Test-RemoteVersionNewer', $s)
        if ($e -lt 0) { throw 'connect-update Test-RemoteVersionNewer missing' }
        # include the unreachable exit block only
        $mid = $cuRaw.Substring($s, $e - $s)
        if ($mid -notmatch 'update check skipped') { throw "unexpected mid block:`n$mid" }
        $cuRaw = $cuRaw.Substring(0, $s) + $newMain + "`n" + $cuRaw.Substring($e)
        Write-Host 'connect-update: Resolve-UpdateEndpoint added'
    } else {
        $cuRaw = $cuRaw.Replace($oldMain, $newMain)
        Write-Host 'connect-update: exact replace OK'
    }
    [IO.File]::WriteAllText($cu, $cuRaw)
} else {
    Write-Host 'connect-update: already has Resolve-UpdateEndpoint'
}

Write-Host 'ALL HARDEN PATCHES DONE'
