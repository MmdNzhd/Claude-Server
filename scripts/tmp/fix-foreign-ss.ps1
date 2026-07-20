Set-Location 'D:\Smart\Claude-Code-Server'
$utf8=New-Object System.Text.UTF8Encoding $false

# --- Win ---
$p='scripts\client\git-mode.ps1'
$t=[IO.File]::ReadAllText((Resolve-Path $p))
$old=@'
    $portDigits = -join (($existingPort.ToCharArray() | Where-Object { $_ -match '[0-9]' }))
    $live = 0
    if ($portDigits) {
        $liveCmd = "ss -ltn 2>/dev/null | grep -cE ':{0}[[:space:]]' || true" -f $portDigits
        $liveRaw = ((SshX $liveCmd) -join '').Trim()
        if ($liveRaw -match '^[0-9]+$') { $live = [int]$liveRaw }
    }
    if (-not $portDigits -or $live -eq 0) {
        Warn ("Cleared stale session from laptop '{0}' (no active tunnel)." -f $existingLu)
        [void](Invoke-SshXChecked -RemoteCmd 'rm -f ~/.claude-connect.conf' -Label 'CLEAR_CONNECT_CONF')
        return $true
    }
'@
$new=@'
    $portDigits = -join (($existingPort.ToCharArray() | Where-Object { $_ -match '[0-9]' }))
    $live = 0
    $ssOk = $false
    if ($portDigits) {
        $liveCmd = "ss -ltn 2>/dev/null | grep -cE ':{0}[[:space:]]' || echo SS_UNKNOWN" -f $portDigits
        $liveRaw = ((SshX $liveCmd) -join '').Trim()
        if ($liveRaw -match '^[0-9]+$') { $live = [int]$liveRaw; $ssOk = $true }
        else {
            Write-GitModeLog "SS:UNKNOWN port=$portDigits raw=$liveRaw - not clearing connect conf" 'WARN'
        }
    }
    # Only auto-clear when ss positively reports zero listeners (or no port in conf).
    if (-not $portDigits -or ($ssOk -and $live -eq 0)) {
        Warn ("Cleared stale session from laptop '{0}' (no active tunnel)." -f $existingLu)
        [void](Invoke-SshXChecked -RemoteCmd 'rm -f ~/.claude-connect.conf' -Label 'CLEAR_CONNECT_CONF')
        return $true
    }
    if (-not $ssOk) {
        # Ambiguous: treat as possibly live and prompt below.
        Write-GitModeLog "FOREIGN_SESSION ss_ambiguous port=$portDigits - prompting" 'WARN'
    }
'@
if($t.Contains($old)){ $t=$t.Replace($old,$new); 'win patched' } else { 'WIN PATTERN MISS' }

[IO.File]::WriteAllText((Resolve-Path $p), $t, $utf8)

# --- Mac ---
$g='scripts\client\git-mode.sh'
$gs=[IO.File]::ReadAllText((Resolve-Path $g))
$oldM=@'
    existing_port="$(printf '%s' "$existing_port" | tr -dc '0-9')"
    if [ -n "$existing_port" ]; then
        live="$(sshx "ss -ltn 2>/dev/null | grep -cE ':${existing_port}[[:space:]]' || true" 2>/dev/null | tr -dc '0-9')"
        [ -z "$live" ] && live=0
    fi
    if [ -z "$existing_port" ] || [ "${live:-0}" = "0" ]; then
        warn "Cleared stale session from laptop '${existing_lu}' (no active tunnel)."
        sshx "rm -f \$HOME/.claude-connect.conf" 2>/dev/null || true
        return 0
    fi
'@
$newM=@'
    existing_port="$(printf '%s' "$existing_port" | tr -dc '0-9')"
    ss_ok=0
    if [ -n "$existing_port" ]; then
        live_raw="$(sshx "ss -ltn 2>/dev/null | grep -cE ':${existing_port}[[:space:]]' || echo SS_UNKNOWN" 2>/dev/null | tr -d '\r\n')"
        if printf '%s' "$live_raw" | grep -Eq '^[0-9]+$'; then
            live="$live_raw"
            ss_ok=1
        else
            live=0
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "SS:UNKNOWN port=$existing_port raw=$live_raw - not clearing connect conf" 'WARN'
            fi
        fi
    fi
    # Only auto-clear when ss positively reports zero listeners (or no port in conf).
    if [ -z "$existing_port" ] || { [ "$ss_ok" = "1" ] && [ "${live:-0}" = "0" ]; }; then
        warn "Cleared stale session from laptop '${existing_lu}' (no active tunnel)."
        sshx "rm -f \$HOME/.claude-connect.conf" 2>/dev/null || true
        return 0
    fi
    if [ "$ss_ok" != "1" ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "FOREIGN_SESSION ss_ambiguous port=$existing_port - prompting" 'WARN'
        fi
    fi
'@
if($gs.Contains($oldM)){ $gs=$gs.Replace($oldM,$newM); 'mac patched' } else { 'MAC PATTERN MISS' }
[IO.File]::WriteAllText((Resolve-Path $g), $gs, $utf8)

$ps=[IO.File]::ReadAllText((Resolve-Path $p))
$gs=[IO.File]::ReadAllText((Resolve-Path $g))
"ss-unknown win=$($ps -match 'SS:UNKNOWN') mac=$($gs -match 'SS:UNKNOWN')"
$err=$null;[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $p),[ref]$null,[ref]$err)
"parse=$($err.Count)"
# keep P0
"seq12=$($gs -match 'seq 1 12' -and $gs -notmatch 'seq 1 4') budget=$($ps -match 'banner_miss_tcp_open_budget')"
