$ErrorActionPreference = 'Stop'
$gm = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$raw = [IO.File]::ReadAllText($gm)
$nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }

if (-not $raw.Contains('function Get-ForeignTunnelPortSet')) {
$insert = @"
function Get-ForeignTunnelPortSet {
    if (`$script:ForeignTunnelPortSet) { return `$script:ForeignTunnelPortSet }
    `$set = New-Object "System.Collections.Generic.HashSet[int]"
    if (`$Cfg -and (Test-Path `$Cfg)) {
        `$line = Get-Content `$Cfg -ErrorAction SilentlyContinue | Where-Object { `$_ -match "^FOREIGN_TUNNEL_PORTS=" } | Select-Object -Last 1
        if (`$line -match "^FOREIGN_TUNNEL_PORTS=(.*)`$") {
            foreach (`$part in @(`$Matches[1] -split "[,\s]+")) {
                `$p = 0
                if ([int]::TryParse(`$part.Trim(), [ref]`$p) -and `$p -gt 0) { [void]`$set.Add(`$p) }
            }
        }
    }
    `$script:ForeignTunnelPortSet = `$set
    return `$set
}

function Save-ForeignTunnelPortSet {
    if (-not `$Cfg) { return }
    `$set = Get-ForeignTunnelPortSet
    `$csv = (@(`$set | Sort-Object) -join ",")
    `$lines = @()
    if (Test-Path `$Cfg) {
        `$lines = @(Get-Content `$Cfg -ErrorAction SilentlyContinue | Where-Object { `$_ -notmatch "^FOREIGN_TUNNEL_PORTS=" })
    }
    if (`$csv) { `$lines += "FOREIGN_TUNNEL_PORTS=`$csv" }
    Set-Content -Path `$Cfg -Value `$lines -Encoding ASCII
}

function Add-ForeignTunnelPort {
    param([Parameter(Mandatory)][int]`$TargetPort)
    if (-not `$TargetPort) { return }
    `$set = Get-ForeignTunnelPortSet
    if (`$set.Add(`$TargetPort)) {
        Save-ForeignTunnelPortSet
        Write-GitModeLog "FOREIGN_PORT remembered port=`$TargetPort" "INFO"
    }
}

function Test-CachedForeignTunnelPort {
    param([Parameter(Mandatory)][int]`$TargetPort)
    `$set = Get-ForeignTunnelPortSet
    if (-not `$set.Contains(`$TargetPort)) { return `$false }
    `$savedPort = `$Port
    `$Port = `$TargetPort
    try {
        `$tcpOpen = `$false
        try { `$tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { `$tcpOpen = `$false }
        if (`$tcpOpen) {
            Write-GitModeLog "ACQUIRE_SKIP: foreign_peer cached port=`$TargetPort" "INFO"
            return `$true
        }
        if (`$set.Remove(`$TargetPort)) { Save-ForeignTunnelPortSet }
        return `$false
    } finally {
        `$Port = `$savedPort
    }
}

"@
  if ($nl -eq "`r`n") { $insert = $insert -replace "(?<!\r)\n", "`r`n" }
  $marker = 'function Get-TunnelHostKeyFingerprint {'
  $idx = $raw.IndexOf($marker)
  if ($idx -lt 0) { throw 'marker missing' }
  $raw = $raw.Insert($idx, $insert)
  Write-Host 'OK helpers inserted'
}

# Cache at start of Get-TunnelHostKeyFingerprint
$fnStart = $raw.IndexOf('function Get-TunnelHostKeyFingerprint {')
$fnEnd = $raw.IndexOf('function Test-TunnelHostKeyMismatch')
if ($fnStart -lt 0 -or $fnEnd -lt 0) { throw 'fn bounds missing' }
$fnBody = $raw.Substring($fnStart, $fnEnd - $fnStart)
if ($fnBody -notmatch 'TunnelHostKeyFpByPort') {
  $needle = "if (-not `$TargetPort) { return '' }"
  $nIdx = $fnBody.IndexOf($needle)
  if ($nIdx -lt 0) { throw 'early return missing' }
  $abs = $fnStart + $nIdx + $needle.Length
  while ($abs -lt $raw.Length -and ($raw[$abs] -eq "`r" -or $raw[$abs] -eq "`n" -or $raw[$abs] -eq ' ')) {
    # consume through end of line only
    if ($raw[$abs] -eq "`n") { $abs++; break }
    $abs++
  }
  $cacheHook = @"
    if (-not `$script:TunnelHostKeyFpByPort) { `$script:TunnelHostKeyFpByPort = @{} }
    `$key = [string]`$TargetPort
    if (`$script:TunnelHostKeyFpByPort.ContainsKey(`$key)) {
        return [string]`$script:TunnelHostKeyFpByPort[`$key]
    }
"@
  if ($nl -eq "`r`n") { $cacheHook = $cacheHook -replace "(?<!\r)\n", "`r`n" }
  $raw = $raw.Insert($abs, $cacheHook + $nl)
  Write-Host 'OK cache read hook'
}

# store before return $fp
$fnStart = $raw.IndexOf('function Get-TunnelHostKeyFingerprint {')
$fnEnd = $raw.IndexOf('function Test-TunnelHostKeyMismatch')
$fnBody = $raw.Substring($fnStart, $fnEnd - $fnStart)
if ($fnBody -notmatch 'TunnelHostKeyFpByPort\[\$key\]\s*=') {
  $retRel = $fnBody.LastIndexOf('return $fp')
  if ($retRel -lt 0) { throw 'return fp missing' }
  $absRet = $fnStart + $retRel
  $lineStart = $raw.LastIndexOf($nl, $absRet)
  if ($lineStart -lt $fnStart) { throw 'line start bad' }
  $lineStart = $lineStart + $nl.Length
  $store = "    `$script:TunnelHostKeyFpByPort[`$key] = `$fp" + $nl
  $raw = $raw.Insert($lineStart, $store)
  Write-Host 'OK cache store'
}

# mismatch Add-Foreign
if ($raw -notmatch 'Add-ForeignTunnelPort -TargetPort \$TargetPort') {
  $token = 'ACQUIRE_SKIP: hostkey_mismatch port=$TargetPort'
  $misIdx = $raw.IndexOf($token)
  if ($misIdx -lt 0) { throw 'mismatch token missing' }
  $eol = $raw.IndexOf("`n", $misIdx)
  $insertMis = '        if (Get-Command Add-ForeignTunnelPort -ErrorAction SilentlyContinue) { Add-ForeignTunnelPort -TargetPort $TargetPort }' + $nl
  $raw = $raw.Insert($eol + 1, $insertMis)
  Write-Host 'OK mismatch remember'
}

# ForeignPeer
$fpFn = $raw.IndexOf('function Test-TunnelPortIsForeignPeer')
$acqFn = $raw.IndexOf('function Acquire-TunnelPort')
$fpBody = $raw.Substring($fpFn, $acqFn - $fpFn)
if ($fpBody -notmatch 'Test-CachedForeignTunnelPort -TargetPort \$TargetPort') {
  $anchor = '$savedPort = $Port'
  $aIdx = $fpBody.IndexOf($anchor)
  if ($aIdx -lt 0) { throw 'savedPort missing' }
  $block = @"
    if (Get-Command Test-CachedForeignTunnelPort -ErrorAction SilentlyContinue) {
        if (Test-CachedForeignTunnelPort -TargetPort `$TargetPort) { return `$true }
    }
"@
  if ($nl -eq "`r`n") { $block = $block -replace "(?<!\r)\n", "`r`n" }
  $raw = $raw.Insert($fpFn + $aIdx, $block + $nl)
  Write-Host 'OK ForeignPeer cache'
}

# Acquire
$acq = $raw.IndexOf('function Acquire-TunnelPort')
$after = $raw.IndexOf('function Test-TunnelUp')
$acqBody = $raw.Substring($acq, $after - $acq)
if ($acqBody -notmatch 'Test-CachedForeignTunnelPort -TargetPort \$port') {
  $loopAnchor = 'if ($port -gt 65535) { continue }'
  $lIdx = $acqBody.IndexOf($loopAnchor)
  if ($lIdx -lt 0) { throw 'loop anchor missing' }
  $abs = $acq + $lIdx + $loopAnchor.Length
  while ($abs -lt $raw.Length -and ($raw[$abs] -eq "`r" -or $raw[$abs] -eq "`n")) { $abs++ }
  $block = @"
        if (Get-Command Test-CachedForeignTunnelPort -ErrorAction SilentlyContinue) {
            if (Test-CachedForeignTunnelPort -TargetPort `$port) { continue }
        }
"@
  if ($nl -eq "`r`n") { $block = $block -replace "(?<!\r)\n", "`r`n" }
  $raw = $raw.Insert($abs, $block + $nl)
  Write-Host 'OK Acquire cache'
}

[IO.File]::WriteAllText($gm, $raw)
Write-Host 'PATCH_GM_DONE'
$v = [IO.File]::ReadAllText($gm)
$need = @(
  'function Get-ForeignTunnelPortSet',
  'TunnelHostKeyFpByPort',
  'Add-ForeignTunnelPort -TargetPort $TargetPort',
  'Test-CachedForeignTunnelPort -TargetPort $TargetPort',
  'Test-CachedForeignTunnelPort -TargetPort $port'
)
foreach ($n in $need) {
  if ($v.Contains($n)) { "HAS $n" } else { throw "MISSING $n" }
}
