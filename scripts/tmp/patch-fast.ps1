$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$gm = Join-Path $root 'scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)

# 1) Cached foreign: trust list without TCP round-trip
$oldCache = @'
function Test-CachedForeignTunnelPort {
    param([Parameter(Mandatory)][int]$TargetPort)
    $set = Get-ForeignTunnelPortSet
    if (-not $set.Contains($TargetPort)) { return $false }
    $savedPort = $Port
    $Port = $TargetPort
    try {
        $tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if ($tcpOpen) {
            Write-GitModeLog "ACQUIRE_SKIP: foreign_peer cached port=$TargetPort" "INFO"
            return $true
        }
        if ($set.Remove($TargetPort)) { Save-ForeignTunnelPortSet }
        return $false
    } finally {
        $Port = $savedPort
    }
}
'@
$newCache = @'
function Test-CachedForeignTunnelPort {
    param([Parameter(Mandatory)][int]$TargetPort)
    $set = Get-ForeignTunnelPortSet
    if (-not $set.Contains($TargetPort)) { return $false }
    # Trust remembered foreign ports without a 500ms SSH TCP probe each time.
    # (Amir / other peers stay pinned until removed from FOREIGN_TUNNEL_PORTS.)
    Write-GitModeLog "ACQUIRE_SKIP: foreign_peer cached port=$TargetPort" "DEBUG"
    return $true
}
'@
$ok = $false
foreach ($o in @($oldCache, ($oldCache -replace "`r`n","`n"))) {
  $n = if ($o.Contains("`r`n")) { $newCache -replace "(?<!\r)`n","`r`n" } else { $newCache -replace "`r`n","`n" }
  if ($g.Contains($o)) { $g = $g.Replace($o, $n); $ok = $true; break }
}
if (-not $ok) {
  # replace by function body markers
  if ($g -match 'Trust remembered foreign') { Write-Host 'SKIP cache already fast' }
  else {
    $i = $g.IndexOf('function Test-CachedForeignTunnelPort')
    $j = $g.IndexOf('function Get-TunnelHostKeyFingerprint')
    if ($i -lt 0 -or $j -lt 0) { throw 'cache fn bounds missing' }
    $ins = $newCache
    if ($g.Contains("`r`n")) { $ins = $ins -replace "(?<!\r)`n","`r`n" }
    $g = $g.Remove($i, $j - $i).Insert($i, $ins)
    Write-Host 'OK cache replaced by bounds'
  }
} else { Write-Host 'OK cache fast' }

# 2) Ensure-SessionTunnel: do NOT re-Acquire when Port already chosen this session
$oldEns = '    $uidStr = ((SshX ''id -u'' 2>$null) -join '''').Trim() -replace ''\D'', ''''
    if ($uidStr) { $null = Acquire-TunnelPort -UidStr $uidStr -CurrentBgTunnel $BgTunnel.Value -ProtectedProcessIds $protectedPids }'
# try reading exact from file
$ensIdx = $g.IndexOf('Remove-LocalOrphanTunnel -TargetPort $Port')
$acqLine = $g.IndexOf('Acquire-TunnelPort -UidStr $uidStr', $ensIdx)
if ($acqLine -lt 0) { throw 'Acquire in Ensure not found' }
# find full two-line block
$uidLine = $g.LastIndexOf('$uidStr = ((SshX', $acqLine)
if ($uidLine -lt 0) { throw 'uidStr line not found' }
$blockEnd = $g.IndexOf("`n", $acqLine)
while ($blockEnd -lt $g.Length -and $g[$blockEnd] -match "[\r\n]") { $blockEnd++ }
# include full acquire line
$lineEnd = $g.IndexOf("`n", $acqLine)
$oldBlock = $g.Substring($uidLine, $lineEnd - $uidLine)
Write-Host "OLD_ENSURE_BLOCK=<<$oldBlock>>"

$newBlock = @'
    $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
    # Fast path: Port already chosen (Initialize-ServerSession / prior Ensure). Re-scanning
    # all slots costs ~5s per call and was the main cold-connect delay.
    if ($uidStr -and -not $Port) {
        $null = Acquire-TunnelPort -UidStr $uidStr -CurrentBgTunnel $BgTunnel.Value -ProtectedProcessIds $protectedPids
        Write-GitModeLog "ENSURE_TUNNEL acquire_empty_port done port=$Port" 'DEBUG'
    } elseif ($uidStr -and $Port) {
        Write-GitModeLog "ENSURE_TUNNEL skip_acquire port=$Port reason=already_set" 'DEBUG'
    }
'@
if ($g.Contains("`r`n")) { $newBlock = $newBlock -replace "(?<!\r)`n","`r`n" }
# match exact old two lines from file
$oldExact = $g.Substring($uidLine, $lineEnd - $uidLine)
# Need to include through end of acquire line only - check if next lines are Release-Stale
$g = $g.Remove($uidLine, $lineEnd - $uidLine).Insert($uidLine, $newBlock.TrimEnd() + $(if ($g.Contains("`r`n")) { "`r`n" } else { "`n" }))
Write-Host 'OK ensure skip acquire'

# 3) Acquire: if we already hold SessionBgTunnel on $Port, return immediately
$acqFn = $g.IndexOf('function Acquire-TunnelPort')
$insertAt = $g.IndexOf('$portBase = 20000', $acqFn)
$early = @'
    # Already bound to a live session tunnel — do not rescan peers/foreign ports.
    if ($Port -and $script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $mine = @($ProtectedProcessIds)
        $mine += [int]$script:SessionBgTunnel.Id
        if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) { $mine += [int]$CurrentBgTunnel.Id }
        $localNow = @(Get-LocalTunnelSshPids -TargetPort $Port)
        foreach ($pid in $localNow) {
            if ($mine -contains [int]$pid) {
                Write-GitModeLog "ACQUIRE_KEEP: session_tunnel port=$Port pid=$pid" 'DEBUG'
                return $true
            }
        }
    }
'@
if ($g.Contains("`r`n")) { $early = $early -replace "(?<!\r)`n","`r`n" }
if ($g.Substring($insertAt, 80) -notmatch 'ACQUIRE_KEEP') {
  $g = $g.Insert($insertAt, $early)
  Write-Host 'OK acquire keep'
} else { Write-Host 'SKIP acquire keep' }

[IO.File]::WriteAllText($gm, $g)

# version bump
$cps = Join-Path $root 'scripts\client\windows\connect.ps1'
$c = [IO.File]::ReadAllText($cps)
$c = [regex]::Replace($c, "ConnectVersion = '20260721\.\d+'", "ConnectVersion = '20260721.12'")
[IO.File]::WriteAllText($cps, $c)
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-version.txt'), '20260721.12')

$errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($gm,[ref]$null,[ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'parse fail' }
Write-Host 'PARSE_OK'

# verify
$v=[IO.File]::ReadAllText($gm)
foreach ($n in @('skip_acquire port=','Trust remembered foreign','ACQUIRE_KEEP: session_tunnel')) {
  if ($v -notmatch [regex]::Escape($n) -and $v -notmatch $n) {
    # loose
  }
}
if ($v -notmatch 'skip_acquire') { throw 'missing skip_acquire' }
if ($v -notmatch 'Trust remembered foreign') { throw 'missing trust foreign' }
if ($v -notmatch 'ACQUIRE_KEEP') { throw 'missing ACQUIRE_KEEP' }
Write-Host 'MARKERS_OK'
Write-Host 'DONE'
