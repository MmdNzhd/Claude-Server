$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$gm = Join-Path $root 'scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
$nl = if ($g.Contains("`r`n")) { "`r`n" } else { "`n" }

# Cache id -u in Ensure
$g = $g.Replace(
  "        `$uidStr = ((SshX 'id -u' 2>`$null) -join '').Trim() -replace '\D', ''",
  @"
        if (-not `$script:ServerUidStr) {
            `$script:ServerUidStr = ((SshX 'id -u' 2>`$null) -join '').Trim() -replace '\D', ''
        }
        `$uidStr = `$script:ServerUidStr
"@
)
# try without extra escaping - read exact
$oldUid = @'
        $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
    # Fast path: Port already chosen (Initialize-ServerSession / prior Ensure). Re-scanning
'@
$newUid = @'
        if (-not $script:ServerUidStr) {
            $script:ServerUidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
        }
        $uidStr = $script:ServerUidStr
    # Fast path: Port already chosen (Initialize-ServerSession / prior Ensure). Re-scanning
'@
$ok = $false
foreach ($pair in @(@($oldUid,$newUid), @(($oldUid -replace "`r`n","`n"), ($newUid -replace "`r`n","`n")))) {
  if ($g.Contains($pair[0])) { $g = $g.Replace($pair[0], $pair[1]); $ok = $true; break }
}
if (-not $ok) { Write-Host 'WARN uid cache skip' } else { Write-Host 'OK uid cache' }

# Before "ENSURE_TUNNEL start" expensive path: adopt live local -R on $Port
$marker = '    Write-GitModeLog "ENSURE_TUNNEL start port=$Port alias=$Alias had_bg=$([bool]$BgTunnel.Value)" ''DEBUG'''
# exact from file
$ensStart = $g.IndexOf('Write-GitModeLog "ENSURE_TUNNEL start port=$Port')
if ($ensStart -lt 0) { throw 'ENSURE start log missing' }
if ($g.Substring([Math]::Max(0,$ensStart-400), 400) -match 'ACQUIRE_ADOPT') {
  Write-Host 'SKIP adopt already'
} else {
  $adopt = @'
    # Fast adopt: local ssh -R already forwarding $Port and server TCP is open.
    if ($Port) {
        $adoptPids = @(Get-LocalTunnelSshPids -TargetPort $Port)
        if ($adoptPids.Count -gt 0) {
            $tcpOpen = $false
            try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
            if ($tcpOpen) {
                $adoptPid = [int]$adoptPids[0]
                $adoptProc = Get-Process -Id $adoptPid -ErrorAction SilentlyContinue
                if ($adoptProc -and -not $adoptProc.HasExited) {
                    $BgTunnel.Value = $adoptProc
                    $script:SessionBgTunnel = $adoptProc
                    $TunnelReused.Value = $true
                    $script:TunnelSyncFailCount = 0
                    $script:TunnelSoftFailCount = 0
                    Write-GitModeLog "ENSURE_TUNNEL reused=1 pid=$adoptPid port=$Port reason=adopt_local_forward" 'INFO'
                    return $true
                }
            }
        }
    }

'@
  if ($nl -eq "`r`n") { $adopt = $adopt -replace "(?<!\r)`n", "`r`n" }
  $g = $g.Insert($ensStart, $adopt)
  Write-Host 'OK adopt local'
}

# When Port already set, skip Release-StaleTunnelPort (extra SSH banner) before spawn —
# only release if we are about to spawn and TCP shows foreign/zombie.
$oldRel = @'
    } elseif ($uidStr -and $Port) {
        Write-GitModeLog "ENSURE_TUNNEL skip_acquire port=$Port reason=already_set" 'DEBUG'
    }

    Release-StaleTunnelPort
'@
$newRel = @'
    } elseif ($uidStr -and $Port) {
        Write-GitModeLog "ENSURE_TUNNEL skip_acquire port=$Port reason=already_set" 'DEBUG'
    }

    # Avoid Release-StaleTunnelPort on the happy path (extra banner SSH ~500ms+).
    # Only clear when server port is open but we have no local -R to adopt.
    $needStaleClear = $false
    if ($Port) {
        $haveLocal = (@(Get-LocalTunnelSshPids -TargetPort $Port).Count -gt 0)
        if (-not $haveLocal) {
            $tcpOpen2 = $false
            try { $tcpOpen2 = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen2 = $false }
            if ($tcpOpen2) { $needStaleClear = $true }
        }
    }
    if ($needStaleClear) {
        Release-StaleTunnelPort
    } else {
        Write-GitModeLog "ENSURE_TUNNEL skip_release_stale port=$Port" 'DEBUG'
    }
'@
$ok2 = $false
foreach ($pair in @(@($oldRel,$newRel), @(($oldRel -replace "`r`n","`n"), ($newRel -replace "`r`n","`n")))) {
  if ($g.Contains($pair[0])) { $g = $g.Replace($pair[0], $pair[1]); $ok2 = $true; break }
}
if (-not $ok2) { Write-Host 'WARN release skip not applied' } else { Write-Host 'OK skip release stale' }

# Initialize-ServerSession: stash uid
$cps = Join-Path $root 'scripts\client\windows\connect.ps1'
$c = [IO.File]::ReadAllText($cps)
$oldInit = '    if (-not (Acquire-TunnelPort -UidStr $uidStr)) {'
$newInit = '    $script:ServerUidStr = $uidStr' + $nl + '    if (-not (Acquire-TunnelPort -UidStr $uidStr)) {'
if ($c.Contains($oldInit) -and $c -notmatch 'ServerUidStr = \$uidStr') {
  $c = $c.Replace($oldInit, $newInit)
  Write-Host 'OK stash uid in Initialize'
}

# Skip second Laptop SSH verify right after setup if we just succeeded Ensure-LaptopSshReady
# Find STEP Verifying laptop SSH - harder; skip for now

$c = [regex]::Replace($c, "ConnectVersion = '20260721\.\d+'", "ConnectVersion = '20260721.14'")
[IO.File]::WriteAllText($cps, $c)
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-version.txt'), '20260721.14')
[IO.File]::WriteAllText($gm, $g)

$errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($gm,[ref]$null,[ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'gm parse' }
$errs2=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($cps,[ref]$null,[ref]$errs2)
if ($errs2 -and $errs2.Count) { $errs2 | ForEach-Object { $_.ToString() }; throw 'cps parse' }

# verify empty ports fix still present
$v=[IO.File]::ReadAllText($gm)
if ($v -notmatch 'Ports = @\(\)') { throw 'empty ports fix lost' }
if ($v -notmatch 'no_probe_ports') { throw 'no_probe lost' }
if ($v -notmatch 'adopt_local_forward') { throw 'adopt lost' }
Write-Host 'ALL_OK'
