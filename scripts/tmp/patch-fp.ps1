$ErrorActionPreference = 'Stop'
$gm = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
$nl = if ($g.Contains("`r`n")) { "`r`n" } else { "`n" }

$fn = $g.IndexOf('function Test-TunnelPortIsForeignPeer')
$acq = $g.IndexOf('function Get-LocalTunnelPortPidMap')
if ($acq -lt 0) { $acq = $g.IndexOf('function Acquire-TunnelPort') }
$body = $g.Substring($fn, $acq - $fn)
if ($body -match 'Closed port cannot be a live foreign') { Write-Host 'already tcp-first'; exit 0 }

# Find: Clear-TunnelBannerCache then Get-TunnelBanner then tcpOpen in ForeignPeer
$anchor = '$savedPort = $Port'
$a = $body.IndexOf($anchor)
if ($a -lt 0) { throw 'savedPort missing' }
# from after setting Port = TargetPort try {
$tryIdx = $body.IndexOf('try {', $a)
$bannerIdx = $body.IndexOf('Clear-TunnelBannerCache', $tryIdx)
$tcpIdx = $body.IndexOf('Test-TunnelPortTcpOpen', $bannerIdx)
if ($bannerIdx -lt 0 -or $tcpIdx -lt 0) { throw "markers banner=$bannerIdx tcp=$tcpIdx" }

# Replace from Clear-TunnelBannerCache through the early-return block
$earlyEnd = $body.IndexOf('# Absolute pin:', $bannerIdx)
if ($earlyEnd -lt 0) { throw 'absolute pin missing' }
$abs = $fn + $bannerIdx
$len = $earlyEnd - $bannerIdx
$replacement = @'
$tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if (-not $tcpOpen) {
            # Closed port cannot be a live foreign peer — skip expensive banner/hostkey SSH.
            return $false
        }
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
        if (-not (Test-TunnelBannerIsWindows -Banner $banner) -and -not $tcpOpen) {
            return $false
        }
        # Absolute pin:
'@
# Don't include "# Absolute pin:" twice - earlyEnd starts at that comment
$replacement = @'
$tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if (-not $tcpOpen) {
            # Closed port cannot be a live foreign peer — skip expensive banner/hostkey SSH.
            return $false
        }
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
'@
if ($nl -eq "`r`n") { $replacement = $replacement -replace "(?<!\r)`n", "`r`n" }
$g = $g.Remove($abs, $len).Insert($abs, $replacement + $nl + '        ')
[IO.File]::WriteAllText($gm, $g)

$errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($gm,[ref]$null,[ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'parse fail' }
if ([IO.File]::ReadAllText($gm) -notmatch 'Closed port cannot be a live foreign') { throw 'tcp-first missing' }
Write-Host 'OK tcp-first'
