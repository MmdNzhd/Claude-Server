$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

function Replace-ExactBlock {
    param(
        [string]$Path,
        [string]$Old,
        [string]$New,
        [switch]$Utf8Bom
    )
    $raw = [System.IO.File]::ReadAllText($Path)
    $rawN = $raw -replace "`r`n", "`n"
    $oldN = $Old -replace "`r`n", "`n"
    $newN = $New -replace "`r`n", "`n"
    if (-not $rawN.Contains($oldN)) {
        throw "Block not found in $Path"
    }
    $outN = $rawN.Replace($oldN, $newN)
    $out = $outN -replace "`n", "`r`n"
    $enc = New-Object System.Text.UTF8Encoding ([bool]$Utf8Bom)
    [System.IO.File]::WriteAllText($Path, $out, $enc)
}

# --- helper + function replace via marker approach ---
$deployPath = Join-Path $root 'publish\deploy-client-bundles.ps1'
$deployN = ([System.IO.File]::ReadAllText($deployPath) -replace "`r`n", "`n")

if ($deployN -notmatch 'function Test-RemoteVersionMatches') {
    $insert = @'
function Test-RemoteVersionMatches {
    param(
        [string]$RemoteVer,
        [string]$ExpectedVersion
    )
    if (-not $RemoteVer) { return $false }
    if (-not $ExpectedVersion) { return $true }
    return ($RemoteVer -eq $ExpectedVersion)
}

'@
    $deployN = $deployN.Replace("function Invoke-RemoteBundleInstall {", ($insert + "function Invoke-RemoteBundleInstall {"))
}

# Replace param block to add ExpectedVersion
$oldParam = @'
    param(
        [Parameter(Mandatory)][string]$ServerTarget,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$BundleZip,
        [Parameter(Mandatory)][string]$InstallScript,
        [string]$SudoPassword = ''
    )
'@
$newParam = @'
    param(
        [Parameter(Mandatory)][string]$ServerTarget,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$BundleZip,
        [Parameter(Mandatory)][string]$InstallScript,
        [string]$SudoPassword = '',
        [string]$ExpectedVersion = ''
    )
'@
if (-not $deployN.Contains(($oldParam -replace "`r`n","`n"))) {
    if ($deployN -match 'ExpectedVersion') {
        Write-Output 'param already has ExpectedVersion'
    } else {
        throw 'param block not found'
    }
} else {
    $deployN = $deployN.Replace(($oldParam -replace "`r`n","`n"), ($newParam -replace "`r`n","`n"))
}

# Fix wait-loop condition: any remoteVer -> must match expected
$oldWait = @'
    if ($sudoExit -ne 0 -and -not $remoteVer) {
        Write-DeployWarn "$Label : sudo password required - opening terminal window..."
        $title = "Claude bundle install - $Label"
        Start-Process cmd.exe -ArgumentList @('/k', "title $title && ssh -t -o ConnectTimeout=15 $ServerTarget `"$installCmd`"")
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            $remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $ServerTarget "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
            if ($remoteVer) { break }
        }
        if (-not $remoteVer) {
            throw "Timed out waiting for $Label install (complete sudo in the opened terminal, then re-run publish or finish-sepidz-deploy.bat)"
        }
    } else {
        $remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $ServerTarget "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
    }

    if ($remoteVer) {
        Write-DeployOk "$Label deployed v$remoteVer on $ServerTarget"
    } else {
        throw "Remote install failed for $Label ($ServerTarget)"
    }
}
'@

$newWait = @'
    if ($sudoExit -ne 0 -and -not (Test-RemoteVersionMatches -RemoteVer $remoteVer -ExpectedVersion $ExpectedVersion)) {
        Write-DeployWarn "$Label : sudo password required - opening terminal window..."
        $title = "Claude bundle install - $Label"
        Start-Process cmd.exe -ArgumentList @('/k', "title $title && ssh -t -o ConnectTimeout=15 $ServerTarget `"$installCmd`"")
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            $remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $ServerTarget "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
            if (Test-RemoteVersionMatches -RemoteVer $remoteVer -ExpectedVersion $ExpectedVersion) { break }
        }
        if (-not (Test-RemoteVersionMatches -RemoteVer $remoteVer -ExpectedVersion $ExpectedVersion)) {
            throw "Timed out waiting for $Label install to reach v$ExpectedVersion (complete sudo in the opened terminal, then re-run publish or finish-*-deploy.bat)"
        }
    } else {
        $remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $ServerTarget "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
    }

    if (-not $remoteVer) {
        throw "Remote install failed for $Label ($ServerTarget): connect-version.txt missing/empty"
    }
    if ($ExpectedVersion -and $remoteVer -ne $ExpectedVersion) {
        throw "Remote version mismatch for $Label ($ServerTarget): expected v$ExpectedVersion, got v$remoteVer"
    }
    Write-DeployOk "$Label deployed v$remoteVer on $ServerTarget"
}
'@

$oldWaitN = $oldWait -replace "`r`n","`n"
$newWaitN = $newWait -replace "`r`n","`n"
if (-not $deployN.Contains($oldWaitN)) {
    if ($deployN -match 'Remote version mismatch') {
        Write-Output 'wait/verify already patched'
    } else {
        throw 'wait/verify block not found'
    }
} else {
    $deployN = $deployN.Replace($oldWaitN, $newWaitN)
}

$oldCall = @'
        Invoke-RemoteBundleInstall -ServerTarget $target.Server -Label $target.Label `
            -BundleZip $zipPath -InstallScript $installScript -SudoPassword $sudoPw
'@
$newCall = @'
        $expectedVer = ''
        $verFile = Join-Path $target.ClientRoot 'windows\connect-version.txt'
        if (Test-Path $verFile) {
            $expectedVer = (Get-Content -LiteralPath $verFile -Raw).Trim()
        }
        if (-not $expectedVer) {
            throw "connect-version.txt missing/empty in $($target.ClientRoot)\windows"
        }
        Write-DeployStep "$($target.Label) : expected package version v$expectedVer"
        Invoke-RemoteBundleInstall -ServerTarget $target.Server -Label $target.Label `
            -BundleZip $zipPath -InstallScript $installScript -SudoPassword $sudoPw `
            -ExpectedVersion $expectedVer
'@
$oldCallN = $oldCall -replace "`r`n","`n"
$newCallN = $newCall -replace "`r`n","`n"
if (-not $deployN.Contains($oldCallN)) {
    if ($deployN -match 'expected package version') {
        Write-Output 'call site already patched'
    } else {
        throw 'call site not found'
    }
} else {
    $deployN = $deployN.Replace($oldCallN, $newCallN)
}

$enc = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($deployPath, ($deployN -replace "`n","`r`n"), $enc)
Write-Output 'OK deploy-client-bundles.ps1'

# --- Test-TunnelUp ---
$gmPath = Join-Path $root 'scripts\client\git-mode.ps1'
$gmN = ([System.IO.File]::ReadAllText($gmPath) -replace "`r`n","`n")
$oldTu = @'
function Test-TunnelUp {
    if (-not $Port) { return $false }
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
            Write-GitModeLog "TUNNEL_UP port=$Port up=$($script:TunnelBannerCacheUp) banner=$($script:TunnelBannerCacheBanner) cache=1" 'TRACE'
            return $script:TunnelBannerCacheUp
        }
    }
    $banner = Get-TunnelBanner
    $up = $script:TunnelBannerCacheUp
    Write-GitModeLog "TUNNEL_UP port=$Port up=$up banner=$banner" 'TRACE'
    return $up
}
'@
$newTu = @'
function Test-TunnelUp {
    if (-not $Port) { return $false }
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
            $up = (Test-TunnelBannerIsWindows -Banner $script:TunnelBannerCacheBanner)
            $script:TunnelBannerCacheUp = $up
            Write-GitModeLog "TUNNEL_UP port=$Port up=$up banner=$($script:TunnelBannerCacheBanner) cache=1" 'TRACE'
            return $up
        }
    }
    $banner = Get-TunnelBanner
    $up = (Test-TunnelBannerIsWindows -Banner $banner)
    $script:TunnelBannerCacheUp = $up
    Write-GitModeLog "TUNNEL_UP port=$Port up=$up banner=$banner" 'TRACE'
    return $up
}
'@
$oldTuN = $oldTu -replace "`r`n","`n"
$newTuN = $newTu -replace "`r`n","`n"
if (-not $gmN.Contains($oldTuN)) {
    if ($gmN -match 'Test-TunnelBannerIsWindows -Banner \$banner') {
        Write-Output 'Test-TunnelUp already patched'
    } else {
        throw 'Test-TunnelUp not found'
    }
} else {
    $gmN = $gmN.Replace($oldTuN, $newTuN)
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($gmPath, ($gmN -replace "`n","`r`n"), $utf8Bom)
    Write-Output 'OK git-mode.ps1'
}

foreach ($p in @($deployPath, $gmPath)) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) {
        throw ("Parse errors in ${p}: " + (($errs | ForEach-Object Message) -join '; '))
    }
}
Write-Output 'OK parse'
