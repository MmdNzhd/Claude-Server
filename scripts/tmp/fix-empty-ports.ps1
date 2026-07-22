$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$gm = Join-Path $root 'scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
$nl = if ($g.Contains("`r`n")) { "`r`n" } else { "`n" }

# 1) Fix Get-ServerOpenTunnelPorts to allow empty Ports
$i = $g.IndexOf('function Get-ServerOpenTunnelPorts')
$j = $g.IndexOf('function Acquire-TunnelPort')
if ($i -lt 0 -or $j -lt 0) { throw "bounds i=$i j=$j" }

$newFn = @'
function Get-ServerOpenTunnelPorts {
    param([int[]]$Ports = @())
    $set = New-Object "System.Collections.Generic.HashSet[int]"
    if ($null -eq $Ports -or @($Ports).Count -eq 0) {
        Write-GitModeLog 'ACQUIRE_BATCH open_ports= probed=0' 'DEBUG'
        return $set
    }
    $list = (@($Ports) | Select-Object -Unique) -join ' '
    # One SSH, parallel short probes — closed ports fail in ~250ms, not 1s serial each.
    $script = @"
for p in $list; do
  ( timeout 0.25 bash -c "exec 3<>/dev/tcp/127.0.0.1/`$p" 2>/dev/null && echo OPEN:`$p ) &
done
wait
"@
    $out = (SshX $script 2>$null) -join "`n"
    foreach ($line in @($out -split "`n")) {
        if ($line -match 'OPEN:(\d+)') { [void]$set.Add([int]$Matches[1]) }
    }
    Write-GitModeLog ("ACQUIRE_BATCH open_ports={0} probed={1}" -f (($set | Sort-Object) -join ','), @($Ports).Count) 'DEBUG'
    return $set
}

'@
if ($nl -eq "`r`n") { $newFn = $newFn -replace "(?<!\r)`n", "`r`n" }
$g = $g.Remove($i, $j - $i).Insert($i, $newFn)

# 2) In Acquire: guard call + when probePorts empty, try free ports that were only "peer_live"
#    from OTHER dead/zombie by allowing reclaim of first non-foreign local-owned OR
#    pick first foreign-cleared slot and force spawn (Release-Stale on our sticky).
# Find the openSet = Get-ServerOpenTunnelPorts line and wrap it
$oldCall = '    $openSet = Get-ServerOpenTunnelPorts -Ports $probePorts'
$newCall = @'
    if (@($probePorts).Count -eq 0) {
        Write-GitModeLog 'ACQUIRE_FAST no_probe_ports (all peer_live/foreign) - trying sticky reclaim' 'WARN'
        $openSet = New-Object "System.Collections.Generic.HashSet[int]"
        # Prefer sticky conf PORT / UI slot even if marked peer_live — may be our orphan.
        $stickyPort = $null
        if ($preferredPort) { $stickyPort = [int]$preferredPort }
        elseif ($null -ne $preferredInt) { $stickyPort = $portBase + [int]$UidStr + [int]$preferredInt }
        if ($stickyPort) {
            $stickySlot = [int]$stickyPort - $portBase - [int]$UidStr
            if ($stickySlot -ge 0 -and $stickySlot -le 9) {
                if (-not (Test-CachedForeignTunnelPort -TargetPort $stickyPort)) {
                    $script:TunnelSlot = $stickySlot
                    $script:Port = $stickyPort
                    # Drop foreign-looking local orphans on this port except protected.
                    $null = Remove-LocalOrphanTunnel -TargetPort $stickyPort -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds
                    Save-TunnelSlot
                    Push-ServerConnectConf
                    Write-GitModeLog ("ACQUIRE_FAST claim_sticky port={0} slot={1} ms={2}" -f $stickyPort, $stickySlot, $sw.ElapsedMilliseconds) 'INFO'
                    return $true
                }
            }
        }
        # Last resort: first non-foreign slot in range (even if peer_live map said busy).
        foreach ($c in $candidates) {
            $port = [int]$c.Port
            $slot = [int]$c.Slot
            if (Test-CachedForeignTunnelPort -TargetPort $port) { continue }
            $script:TunnelSlot = $slot
            $script:Port = $port
            $null = Remove-LocalOrphanTunnel -TargetPort $port -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds
            Save-TunnelSlot
            Push-ServerConnectConf
            Write-GitModeLog ("ACQUIRE_FAST claim_busy_fallback port={0} slot={1} ms={2}" -f $port, $slot, $sw.ElapsedMilliseconds) 'WARN'
            return $true
        }
        $script:Port = $portBase + [int]$UidStr
        $script:TunnelSlot = 0
        Write-GitModeLog ("ACQUIRE_FAST fail_empty_probe ms={0}" -f $sw.ElapsedMilliseconds) 'WARN'
        return $false
    }
    $openSet = Get-ServerOpenTunnelPorts -Ports $probePorts
'@
if ($nl -eq "`r`n") { $newCall = $newCall -replace "(?<!\r)`n", "`r`n" }
if (-not $g.Contains($oldCall)) { throw 'openSet call not found' }
$g = $g.Replace($oldCall, $newCall.TrimEnd())

[IO.File]::WriteAllText($gm, $g)

# 3) Speed: cache uid -u for session; skip redundant script hash SSH in Initialize if possible
# Bump version
$cps = Join-Path $root 'scripts\client\windows\connect.ps1'
$c = [IO.File]::ReadAllText($cps)
$c = [regex]::Replace($c, "ConnectVersion = '20260721\.\d+'", "ConnectVersion = '20260721.14'")
[IO.File]::WriteAllText($cps, $c)
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-version.txt'), '20260721.14')

$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($gm, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'parse fail' }

# sanity: empty ports must not throw
$v = [IO.File]::ReadAllText($gm)
if ($v -notmatch 'param\(\[int\[\]\]\$Ports = @\(\)\)') { throw 'Ports default missing' }
if ($v -notmatch 'no_probe_ports') { throw 'no_probe guard missing' }
Write-Host 'PARSE_OK FIX_OK'
