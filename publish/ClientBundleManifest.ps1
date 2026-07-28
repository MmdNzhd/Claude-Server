#Requires -Version 5.1
# Shared helpers for the canonical client-bundle-manifest.tsv

function Get-ClientBundleManifestPath {
    param([string]$ProjectRoot)
    if (-not $ProjectRoot) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }
    $p = Join-Path $ProjectRoot 'publish\client-bundle-manifest.tsv'
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing client-bundle-manifest.tsv: $p" }
    return $p
}

function Get-ClientBundleManifestEntries {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path = Get-ClientBundleManifestPath -ProjectRoot $ProjectRoot
    $entries = New-Object System.Collections.Generic.List[object]
    Get-Content -LiteralPath $path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $parts = $line -split "`t"
        if ($parts.Count -lt 3) { throw "Bad manifest line (need kind`tname`tsrc): $line" }
        $entries.Add([pscustomobject]@{
            Kind   = $parts[0].Trim().ToLowerInvariant()
            Name   = $parts[1].Trim()
            SrcRel = ($parts[2].Trim() -replace '/', '\')
        }) | Out-Null
    }
    if ($entries.Count -lt 10) { throw "Manifest too short: $($entries.Count) entries" }
    # Return the List directly. Do NOT `return ,$array` + caller `@()` — that nests the
    # array as one element so foreach runs once and $e.Name becomes "a b c ..." (MAX_PATH).
    return $entries
}

function Get-NextConnectVersion {
    param([Parameter(Mandatory)][string]$Current)
    $cur = ($Current + '').Trim()
    if ($cur -notmatch '^(\d{8})\.(\d+)$') {
        throw "Unexpected connect version '$cur' (want YYYYMMDD.N)"
    }
    $day = $Matches[1]
    $n = [int]$Matches[2] + 1
    return ('{0}.{1}' -f $day, $n)
}

function Set-RepoConnectVersion {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Version
    )
    $winVer = Join-Path $ProjectRoot 'scripts\client\windows\connect-version.txt'
    $macVer = Join-Path $ProjectRoot 'scripts\client\mac\connect-version.txt'
    $winPs1 = Join-Path $ProjectRoot 'scripts\client\windows\connect.ps1'
    $macSh  = Join-Path $ProjectRoot 'scripts\client\mac\connect.sh'
    foreach ($p in @($winVer, $macVer, $winPs1, $macSh)) {
        if (-not (Test-Path -LiteralPath $p)) { throw "Missing version target: $p" }
    }
    [System.IO.File]::WriteAllText($winVer, $Version + "`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($macVer, $Version + "`n", [System.Text.UTF8Encoding]::new($false))

    $ps1 = Get-Content -LiteralPath $winPs1 -Raw
    $ps12 = [regex]::Replace($ps1, "\`$script:ConnectVersion\s*=\s*'[^']*'", "`$script:ConnectVersion = '$Version'")
    if ($ps12 -eq $ps1) { throw "connect.ps1 ConnectVersion assignment not found/replaced" }
    [System.IO.File]::WriteAllText($winPs1, $ps12, [System.Text.UTF8Encoding]::new($false))

    $sh = Get-Content -LiteralPath $macSh -Raw
    $sh2 = [regex]::Replace($sh, "CONNECT_VERSION='[^']*'", "CONNECT_VERSION='$Version'")
    if ($sh2 -eq $sh) { throw "connect.sh CONNECT_VERSION assignment not found/replaced" }
    # keep LF for mac shell
    $sh2 = $sh2 -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllBytes($macSh, [System.Text.UTF8Encoding]::new($false).GetBytes($sh2))

    # Keep client-update-policy.json "latest" in lockstep with ConnectVersion.
    # If latest lags and someone hot-patches policy on the live share after deploy,
    # checksums.txt still has the old hash → client "Update checksum failed" (live 2026-07-28).
    $policyPath = Join-Path $ProjectRoot 'scripts\server\client-update-policy.json'
    if (Test-Path -LiteralPath $policyPath) {
        $pol = Get-Content -LiteralPath $policyPath -Raw
        $pol2 = [regex]::Replace($pol, '("latest"\s*:\s*")[^"]*(")', "`${1}$Version`${2}")
        if ($pol2 -eq $pol -and $pol -notmatch [regex]::Escape('"latest"') ) {
            throw "client-update-policy.json missing latest field"
        }
        if ($pol2 -ne $pol) {
            [System.IO.File]::WriteAllText($policyPath, $pol2.TrimEnd() + "`n", [System.Text.UTF8Encoding]::new($false))
        }
    }
}

function Build-ClientBundleStageFromRepo {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$StageDir,
        [string]$ExePath = '',
        [string]$SmartServer = 'smart@192.168.210.240',
        [switch]$AllowMissingExe
    )
    $entries = Get-ClientBundleManifestEntries -ProjectRoot $ProjectRoot
    if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $StageDir 'windows')
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $StageDir 'mac')

    $exeResolved = $ExePath
    foreach ($e in $entries) {
        if ($e.SrcRel -eq 'SPECIAL:LIVE_EXE') {
            if (-not $exeResolved) {
                $tmpExe = Join-Path $env:TEMP 'cc-live.exe'
                Write-Host "  Reusing live Claude-Connect.exe from $SmartServer (no rebuild)..." -ForegroundColor Cyan
                # Prefer call operator over Start-Process (ExitCode can be null; path quirks).
                & scp -o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no `
                    -o IdentitiesOnly=yes -o IdentityAgent=none -q `
                    "${SmartServer}:/usr/local/share/claude-client/Claude-Connect.exe" $tmpExe
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmpExe)) {
                    if ($AllowMissingExe) {
                        Write-Host '  WARN: live EXE missing - bundle will ship without Claude-Connect.exe' -ForegroundColor Yellow
                        continue
                    }
                    throw "Failed to fetch live Claude-Connect.exe from $SmartServer"
                }
                $exeResolved = $tmpExe
            }
            $dst = Join-Path $StageDir ('windows\' + $e.Name)
            $parent = Split-Path $dst -Parent
            if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Force -Path $parent }
            try {
                [System.IO.File]::Copy([string]$exeResolved, [string]$dst, $true)
            } catch {
                throw ("EXE copy failed srcLen={0} dstLen={1} src={2} dst={3} err={4}" -f `
                    ([string]$exeResolved).Length, ([string]$dst).Length, $exeResolved, $dst, $_.Exception.Message)
            }
            continue
        }
        $src = Join-Path $ProjectRoot $e.SrcRel
        if (-not (Test-Path -LiteralPath $src)) { throw "Manifest source missing: $($e.SrcRel)" }
        $dstRel = if ($e.Kind -eq 'mac') { "mac\$($e.Name)" } else { "windows\$($e.Name)" }
        $dst = Join-Path $StageDir $dstRel
        $parent = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Force -Path $parent }
        try {
            [System.IO.File]::Copy([string]$src, [string]$dst, $true)
        } catch {
            throw ("file copy failed name={0} srcLen={1} dstLen={2} src={3} dst={4} err={5}" -f `
                $e.Name, ([string]$src).Length, ([string]$dst).Length, $src, $dst, $_.Exception.Message)
        }
    }
    return $StageDir
}
