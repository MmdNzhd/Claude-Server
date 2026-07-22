$ErrorActionPreference = "Stop"
$root = "D:\Smart\Claude-Code-Server"

# --- 1) connect.ps1 elevate ---
$cps = Join-Path $root "scripts\client\windows\connect.ps1"
$c = [IO.File]::ReadAllText($cps)
$oldElev = @"
        try {
            `$p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList `$elevArgs -PassThru -Wait
            exit `$(if (`$null -ne `$p -and `$null -ne `$p.ExitCode) { `$p.ExitCode } else { 1 })
        } catch {
"@
# Use literal without extra escaping - file content as read
$oldElev = @'
        try {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevArgs -PassThru -Wait
            exit $(if ($null -ne $p -and $null -ne $p.ExitCode) { $p.ExitCode } else { 1 })
        } catch {
'@
$newElev = @'
        try {
            # Do NOT -Wait: waiting unelevated parent leaves a second console open all session.
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevArgs | Out-Null
            exit 0
        } catch {
'@
if (-not $c.Contains($oldElev)) { throw "elevate Wait block not found" }
$c = $c.Replace($oldElev, $newElev)
if ($c -notmatch "ConnectVersion = '20260721\.9'") { throw "version .9 not found" }
$c = $c.Replace("ConnectVersion = '20260721.9'", "ConnectVersion = '20260721.10'")
[IO.File]::WriteAllText($cps, $c)
Write-Host "OK connect.ps1"

[IO.File]::WriteAllText((Join-Path $root "scripts\client\windows\connect-version.txt"), "20260721.10")
Write-Host "OK version txt"

# --- 2) git-mode.ps1 ---
$gm = Join-Path $root "scripts\client\git-mode.ps1"
$g = [IO.File]::ReadAllText($gm)

if ($g.Contains("function Get-ForeignTunnelPortSet")) {
    Write-Host "SKIP foreign helpers already present"
} else {
    $oldGetFp = @'
function Get-TunnelHostKeyFingerprint {
    param([Parameter(Mandatory)][int]$TargetPort)
    if (-not $TargetPort) { return '' }
    # ssh-keyscan on the server loopback reverse port; fingerprint is stable per laptop sshd.
    $out = (SshX "timeout 4 ssh-keyscan -p $TargetPort -T 3 -t ed25519,rsa,ecdsa 127.0.0.1 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print `$2}' | head -1") -join ''
    $fp = (($out -replace "`r", '') -replace '\s', '').Trim()
    if ($fp -and $fp -notmatch '^(SHA256:|MD5:)') { $fp = '' }
    if ($fp) {
        Write-GitModeLog "HOSTKEY_FP scan port=$TargetPort fp=$fp" 'DEBUG'
    }
    return $fp
}
'@
    $newGetFp = @'
function Get-ForeignTunnelPortSet {
    if ($script:ForeignTunnelPortSet) { return $script:ForeignTunnelPortSet }
    $set = New-Object "System.Collections.Generic.HashSet[int]"
    if ($Cfg -and (Test-Path $Cfg)) {
        $line = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match "^FOREIGN_TUNNEL_PORTS=" } | Select-Object -Last 1
        if ($line -match "^FOREIGN_TUNNEL_PORTS=(.*)$") {
            foreach ($part in @($Matches[1] -split "[,\s]+")) {
                $p = 0
                if ([int]::TryParse($part.Trim(), [ref]$p) -and $p -gt 0) { [void]$set.Add($p) }
            }
        }
    }
    $script:ForeignTunnelPortSet = $set
    return $set
}

function Save-ForeignTunnelPortSet {
    if (-not $Cfg) { return }
    $set = Get-ForeignTunnelPortSet
    $csv = (@($set | Sort-Object) -join ",")
    $lines = @()
    if (Test-Path $Cfg) {
        $lines = @(Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^FOREIGN_TUNNEL_PORTS=" })
    }
    if ($csv) { $lines += "FOREIGN_TUNNEL_PORTS=$csv" }
    Set-Content -Path $Cfg -Value $lines -Encoding ASCII
}

function Add-ForeignTunnelPort {
    param([Parameter(Mandatory)][int]$TargetPort)
    if (-not $TargetPort) { return }
    $set = Get-ForeignTunnelPortSet
    if ($set.Add($TargetPort)) {
        Save-ForeignTunnelPortSet
        Write-GitModeLog "FOREIGN_PORT remembered port=$TargetPort" "INFO"
    }
}

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

function Get-TunnelHostKeyFingerprint {
    param([Parameter(Mandatory)][int]$TargetPort)
    if (-not $TargetPort) { return '' }
    if (-not $script:TunnelHostKeyFpByPort) { $script:TunnelHostKeyFpByPort = @{} }
    $key = [string]$TargetPort
    if ($script:TunnelHostKeyFpByPort.ContainsKey($key)) {
        return [string]$script:TunnelHostKeyFpByPort[$key]
    }
    # ssh-keyscan on the server loopback reverse port; fingerprint is stable per laptop sshd.
    $out = (SshX "timeout 4 ssh-keyscan -p $TargetPort -T 3 -t ed25519,rsa,ecdsa 127.0.0.1 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print `$2}' | head -1") -join ''
    $fp = (($out -replace "`r", '') -replace '\s', '').Trim()
    if ($fp -and $fp -notmatch '^(SHA256:|MD5:)') { $fp = '' }
    $script:TunnelHostKeyFpByPort[$key] = $fp
    if ($fp) {
        Write-GitModeLog "HOSTKEY_FP scan port=$TargetPort fp=$fp" 'DEBUG'
    }
    return $fp
}
'@
    if (-not $g.Contains($oldGetFp)) { throw "Get-TunnelHostKeyFingerprint block not found exactly" }
    $g = $g.Replace($oldGetFp, $newGetFp)
    Write-Host "OK inserted foreign helpers"
}

$oldMismatch = @'
    if ($fp -ne $stored) {
        Write-GitModeLog "ACQUIRE_SKIP: hostkey_mismatch port=$TargetPort got=$fp want=$stored" 'INFO'
        return $true
    }
'@
$newMismatch = @'
    if ($fp -ne $stored) {
        Write-GitModeLog "ACQUIRE_SKIP: hostkey_mismatch port=$TargetPort got=$fp want=$stored" 'INFO'
        if (Get-Command Add-ForeignTunnelPort -ErrorAction SilentlyContinue) {
            Add-ForeignTunnelPort -TargetPort $TargetPort
        }
        return $true
    }
'@
if ($g.Contains($oldMismatch)) {
    $g = $g.Replace($oldMismatch, $newMismatch)
    Write-Host "OK mismatch remember"
} elseif ($g.Contains("Add-ForeignTunnelPort -TargetPort")) {
    Write-Host "SKIP mismatch already patched"
} else { throw "mismatch block not found" }

$oldForeignStart = @'
    $savedPort = $Port
    $Port = $TargetPort
    try {
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
'@
$newForeignStart = @'
    if (Get-Command Test-CachedForeignTunnelPort -ErrorAction SilentlyContinue) {
        if (Test-CachedForeignTunnelPort -TargetPort $TargetPort) { return $true }
    }
    $savedPort = $Port
    $Port = $TargetPort
    try {
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
'@
if ($g.Contains("Test-CachedForeignTunnelPort -TargetPort `$TargetPort) { return `$true }") -or $g.Contains('Test-CachedForeignTunnelPort -TargetPort $TargetPort) { return $true }')) {
    Write-Host "SKIP foreign start already patched"
} elseif ($g.Contains($oldForeignStart)) {
    $g = $g.Replace($oldForeignStart, $newForeignStart)
    Write-Host "OK foreign start cache check"
} else { throw "foreign start block not found" }

$oldAcquireLoop = @'
    foreach ($slot in $trySlots) {
        $port = $portBase + [int]$UidStr + $slot
        if ($port -gt 65535) { continue }
        if (Test-TunnelPortOccupiedByPeer -TargetPort $port -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) {
'@
$newAcquireLoop = @'
    foreach ($slot in $trySlots) {
        $port = $portBase + [int]$UidStr + $slot
        if ($port -gt 65535) { continue }
        if (Get-Command Test-CachedForeignTunnelPort -ErrorAction SilentlyContinue) {
            if (Test-CachedForeignTunnelPort -TargetPort $port) { continue }
        }
        if (Test-TunnelPortOccupiedByPeer -TargetPort $port -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) {
'@
if ($g.Contains('Test-CachedForeignTunnelPort -TargetPort $port) { continue }')) {
    Write-Host "SKIP acquire loop already patched"
} elseif ($g.Contains($oldAcquireLoop)) {
    $g = $g.Replace($oldAcquireLoop, $newAcquireLoop)
    Write-Host "OK acquire loop cache check"
} else { throw "acquire loop block not found" }

[IO.File]::WriteAllText($gm, $g)
Write-Host "OK git-mode.ps1 written"

# --- 3) test ---
$tp = Join-Path $root "scripts\client\tests\test-connect-pipeline.ps1"
$t = [IO.File]::ReadAllText($tp)
if ($t -notmatch 'elevate does not -Wait') {
    $old = 'Assert ($src -match ''Start-ProcessAsInteractiveUser|Start-Process powershell\.exe -Verb RunAs'') "$rel self-elevates to administrator on launch"'
    $new = $old + "`r`n    Assert (`$src -notmatch 'Verb RunAs -ArgumentList `$elevArgs -PassThru -Wait') `"`$rel elevate does not -Wait (avoids stuck unelevated console)`""
    # fix - the Assert line uses $src and $rel in the file literally
    $oldLit = 'Assert ($src -match ''Start-ProcessAsInteractiveUser|Start-Process powershell\.exe -Verb RunAs'') "$rel self-elevates to administrator on launch"'
    # Read actual line from file
    $line = ($t -split "`n" | Where-Object { $_ -match 'self-elevates to administrator' } | Select-Object -First 1)
    if (-not $line) { throw "test line not found" }
    $insert = $line.TrimEnd("`r") + "`r`n    Assert (`$src -notmatch 'Verb RunAs -ArgumentList `$elevArgs -PassThru -Wait') `"`$rel elevate does not -Wait (avoids stuck unelevated console)`""
    # Actually in the file $src is literal dollar-src. Build carefully.
    $addLine = '    Assert ($src -notmatch ''Verb RunAs -ArgumentList \$elevArgs -PassThru -Wait'') "$rel elevate does not -Wait (avoids stuck unelevated console)"'
    # The test file uses single-quoted regex inside. Mirror style of neighboring asserts.
    $addLine = "    Assert (`$src -notmatch 'Verb RunAs -ArgumentList `$elevArgs -PassThru -Wait') `"`$rel elevate does not -Wait (avoids stuck unelevated console)`""
}

# Simpler test patch via line insert
$lines = [IO.File]::ReadAllLines($tp)
$out = New-Object System.Collections.Generic.List[string]
$done = $false
foreach ($ln in $lines) {
    [void]$out.Add($ln)
    if (-not $done -and $ln -match 'self-elevates to administrator') {
        [void]$out.Add('    Assert ($src -notmatch ''Verb RunAs -ArgumentList \$elevArgs -PassThru -Wait'') "$rel elevate does not -Wait (avoids stuck unelevated console)"')
        $done = $true
    }
}
if (-not $done) { throw "could not insert test assert" }
if ($t -notmatch 'elevate does not -Wait') {
    [IO.File]::WriteAllLines($tp, $out)
    Write-Host "OK test assert"
} else { Write-Host "SKIP test already has assert" }

Write-Host "PATCH_DONE"
