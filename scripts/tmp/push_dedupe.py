from pathlib import Path
import re
gm = Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1')
gt = gm.read_text(encoding='utf-8')
m = re.search(r'(?s)function Push-ServerConnectConf \{.*?^\}\r?\n\r?\nfunction Read-RetryQuitKey', gt, re.M)
if not m:
    raise SystemExit('push not found')

new = r'''function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Preserve existing server ACTIVE_MOUNT unless caller clears or sets explicitly.
    # Speed (stable): preserve+write+self-heal in ONE SSH (same semantics as before).
    $preferAm = ''
    if (-not $ClearActiveMount) {
        if (-not [string]::IsNullOrWhiteSpace($ActiveMount)) {
            $preferAm = [string]$ActiveMount
        } elseif ($script:ActiveProjectId) {
            $preferAm = [string]$script:ActiveProjectId
        }
    }
    $clearFlag = if ($ClearActiveMount) { '1' } else { '0' }
    # Dedupe identical pushes within a few seconds (startup called this twice).
    $dedupeKey = "{0}|{1}|{2}|{3}|{4}" -f $LaptopUser, $Port, $mode, $preferAm, $clearFlag
    if ($script:LastPushConfKey -eq $dedupeKey -and $script:LastPushConfAt -and
        ((Get-Date) - $script:LastPushConfAt).TotalSeconds -lt 8) {
        Write-GitModeLog "PUSH_CONF skip_duplicate key=$dedupeKey" 'DEBUG'
        return
    }
    $lu = ($LaptopUser -replace "'", "'\''")
    $modeEsc = ($mode -replace "'", "'\''")
    $preferEsc = ($preferAm -replace "'", "'\''")
    $portEsc = ("$Port" -replace "'", "'\''")
    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode prefer_mount=$preferAm clear=$ClearActiveMount" 'DEBUG'
    $remote = @(
        'set +e'
        "CLEAR='$clearFlag'"
        "PREFER='$preferEsc'"
        "LU='$lu'"
        "PORT='$portEsc'"
        "MODE='$modeEsc'"
        'AM=""'
        'if [ "$CLEAR" = "1" ]; then AM=""'
        'elif [ -n "$PREFER" ]; then AM="$PREFER"'
        'else AM=$(grep -E "^ACTIVE_MOUNT=" "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)'
        'fi'
        'mkdir -p "$HOME/.local/bin"'
        'printf "LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n" "$LU" "$PORT" "$MODE" "$AM" > "$HOME/.claude-connect.conf"'
        'chmod 600 "$HOME/.claude-connect.conf" 2>/dev/null || true'
        '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || "$HOME/.local/bin/claude-self-heal" --quiet 2>/dev/null || true'
        'true'
    ) -join '; '
    SshX $remote 2>$null | Out-Null
    $script:LastPushConfKey = $dedupeKey
    $script:LastPushConfAt = Get-Date
}

function Read-RetryQuitKey'''

gt = gt[:m.start()] + new + gt[m.end():]
if gt.count('function Push-ServerConnectConf') != 1:
    raise SystemExit('push count')
if gt.count('function Read-RetryQuitKey') != 1:
    raise SystemExit('retry count')
gm.write_text(gt, encoding='utf-8', newline='\n')
print('push dedupe ok')
