from pathlib import Path
import re
gm = Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1')
gt = gm.read_text(encoding='utf-8')

# Replace broken Warn-ForeignServerSession function entirely up to Push-ServerConnectConf
m = re.search(r'(?s)function Warn-ForeignServerSession \{.*?^\}\r?\n\r?\nfunction Push-ServerConnectConf', gt, re.M)
if not m:
    raise SystemExit('warn block not found')

new = r'''function Warn-ForeignServerSession {
    # Return $true to continue, $false when user aborts a likely wrong-account takeover.
    # Self-heal: stale conf + no listening reverse tunnel -> clear and continue.
    # Speed (stable): one SSH reads conf (+ live port check when foreign), instead of 3-4 greps.
    $probeCmd = 'set +e; CONF="$HOME/.claude-connect.conf"; LU=""; OS=""; PORT=""; if [ -f "$CONF" ]; then LU=$(grep -E "^LAPTOP_USER=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); OS=$(grep -E "^LAPTOP_OS=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); PORT=$(grep -E "^TUNNEL_PORT=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); fi; printf "LU=%s\nOS=%s\nPORT=%s\n" "$LU" "$OS" "$PORT"'
    $probe = @((SshX $probeCmd) -join "`n")
    $existingLu = ''; $existingOs = ''; $existingPort = ''
    foreach ($ln in ($probe -split "`r?`n")) {
        if ($ln -match '^LU=(.*)$') { $existingLu = $Matches[1].Trim() }
        elseif ($ln -match '^OS=(.*)$') { $existingOs = $Matches[1].Trim() }
        elseif ($ln -match '^PORT=(.*)$') { $existingPort = $Matches[1].Trim() }
    }
    if (-not $existingLu) { return $true }
    $mine = if ($script:LaptopUser) { $script:LaptopUser } elseif ($env:USERNAME) { $env:USERNAME } else { $env:USER }
    if ($existingLu -eq $mine) { return $true }

    $portDigits = -join (($existingPort.ToCharArray() | Where-Object { $_ -match '[0-9]' }))
    $live = 0
    if ($portDigits) {
        $liveCmd = "ss -ltn 2>/dev/null | grep -cE ':{0}[[:space:]]' || true" -f $portDigits
        $liveRaw = ((SshX $liveCmd) -join '').Trim()
        if ($liveRaw -match '^[0-9]+$') { $live = [int]$liveRaw }
    }
    if (-not $portDigits -or $live -eq 0) {
        Warn ("Cleared stale session from laptop '{0}' (no active tunnel)." -f $existingLu)
        SshX 'rm -f ~/.claude-connect.conf' 2>$null | Out-Null
        return $true
    }

    $who = if ($RemoteUser) { $RemoteUser } else { '?' }
    $osTag = if ($existingOs) { " ($existingOs)" } else { '' }
    Warn ("Server account '{0}' is already used by laptop '{1}'{2} (tunnel active)." -f $who, $existingLu, $osTag)
    Warn ("Your laptop user is '{0}'. Taking over will disconnect them." -f $mine)

    $thisOs = 'windows'
    if ($existingOs -and $existingOs -ne $thisOs) {
        Warn ("OS mismatch ({0} vs {1}) - confirm this is your server account." -f $existingOs, $thisOs)
    }
    $choice = if (Get-Command Read-ConnectPrompt -ErrorAction SilentlyContinue) {
        (Read-ConnectPrompt '    Continue and take over that session? [y/N]' -Tag 'FOREIGN_SESSION').Trim().ToLowerInvariant()
    } else { (Read-Host '    Continue and take over that session? [y/N]').Trim().ToLowerInvariant() }
    Write-GitModeLog "DECISION: foreign_session_takeover=$choice" 'WARN'

    if ($choice -ne 'y' -and $choice -ne 'yes') {
        Warn 'Aborted. Fix username with: connect.bat -Setup'
        return $false
    }
    return $true
}

function Push-ServerConnectConf'''

gt = gt[:m.start()] + new + gt[m.end():]
# m ended with 'function Push-ServerConnectConf' consumed - new ends with same, then rest is ` {`
if gt.count('function Warn-ForeignServerSession') != 1:
    raise SystemExit('warn count')
if gt.count('function Push-ServerConnectConf') != 1:
    raise SystemExit('push count')
gm.write_text(gt, encoding='utf-8', newline='\n')
print('fixed warn')
