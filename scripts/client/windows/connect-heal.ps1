#Requires -Version 5.1
# connect-heal.ps1 - repair broken/outdated client folders.
# Smart: may redirect publish/dated folders to Desktop\Claude-Connect.
# Sepidz: NEVER redirect/copy from Smart Claude-Connect or claude-code-client.
# Exit 0 = continue in -Here (may have healed in place)
# Exit 2 = caller must relaunch marker dir connect.bat and exit
# Exit 1 = unexpected failure (caller continues cautiously)

param(
    [Parameter(Mandatory = $true)]
    [string]$Here,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $Here.TrimEnd('\', '/')
$CanonSmart = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$CanonSepidz = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Sepidz'
$StableSmart = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client\windows'
$StableSepidz = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz\claude-code\windows'
$RelaunchMarker = Join-Path $env:TEMP 'claude-connect-relaunch.dir'

$Essential = @(
    'connect.bat',
    'connect-boot.ps1',
    'connect-heal.ps1',
    'connect-bootstrap.ps1',
    'connect.ps1',
    'connect-update.ps1',
    'cursor-proxy-sidecar.ps1',
    'connect-ui.ps1',
    'connect-diagnostic.ps1',
    'editor-launch.ps1',
    'git-mode.ps1',
    'cursor-auth-laptop.ps1',
    'windows-mcp-laptop.ps1',
    'connect-version.txt',
    'connect-rider.bat'
)

function Write-HealLog {
    param([string]$Message, [string]$Level = 'WARN')
    try {
        $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $f = Join-Path $dir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = $env:CLAUDE_CONNECT_RUN_ID
        if (-not $sid) { $sid = '-' }
        $line = '[{0}] [{1}] [{2}] {3}' -f $ts, $Level, $sid, $Message
        [IO.File]::AppendAllText($f, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    } catch {}
}

function Test-IsSepidzClientDir {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    if ($Dir -match '(?i)claude-code-sepidz|Claude-Connect-Sepidz') { return $true }
    $ps1 = Join-Path $Dir 'connect.ps1'
    if (-not (Test-Path -LiteralPath $ps1)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $ps1 -Raw -ErrorAction Stop
        # Match ONLY the $ServerIP assignment. Smart connect.ps1 also mentions
        # 192.168.250.70 in guard/compare code - a bare IP match false-positives Sepidz.
        if ($raw -match '(?m)^\s*\$ServerIP\s*=\s*[''"]192\.168\.250\.70[''"]') { return $true }
        if ($raw -match '(?m)^\s*\$ServerIP\s*=\s*[''"]192\.168\.210\.240[''"]') { return $false }
    } catch {}
    return $false
}

function Get-ClientDirVersion {
    param([string]$Dir)
    try {
        $vf = Join-Path $Dir 'connect-version.txt'
        if (-not (Test-Path -LiteralPath $vf)) { return '0' }
        $v = (Get-Content -LiteralPath $vf -TotalCount 1 -ErrorAction Stop).Trim()
        if ($v) { return $v }
    } catch {}
    return '0'
}

function Compare-ClientVersion {
    param([string]$A, [string]$B)
    if ($A -eq $B) { return 0 }
    if ($A -match '^(\d{8})\.(\d+)$') {
        $ad = [int]$Matches[1]; $an = [int]$Matches[2]
        if ($B -match '^(\d{8})\.(\d+)$') {
            $bd = [int]$Matches[1]; $bn = [int]$Matches[2]
            if ($ad -ne $bd) { return [Math]::Sign($ad - $bd) }
            return [Math]::Sign($an - $bn)
        }
    }
    return [string]::CompareOrdinal($A, $B)
}

function Test-GoodClientDir {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    if (-not (Test-Path -LiteralPath $Dir)) { return $false }
    foreach ($n in @('connect.bat', 'connect.ps1', 'connect-update.ps1', 'cursor-proxy-sidecar.ps1', 'connect-version.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir $n))) { return $false }
    }
    try {
        $raw = Get-Content -LiteralPath (Join-Path $Dir 'connect-update.ps1') -Raw -ErrorAction Stop
        if ($raw -match 'UpdateEndpointTarget') { return $false }
    } catch { return $false }
    return $true
}

function Copy-ClientFiles {
    param([string]$Src, [string]$Dst)
    New-Item -ItemType Directory -Force -Path $Dst | Out-Null
    $n = 0
    foreach ($name in $Essential) {
        $s = Join-Path $Src $name
        if (Test-Path -LiteralPath $s) {
            Copy-Item -LiteralPath $s -Destination (Join-Path $Dst $name) -Force
            $n++
        }
    }
    return $n
}

function Get-CandidateDirs {
    param([bool]$ForSepidz)
    $list = New-Object System.Collections.Generic.List[string]
    if ($ForSepidz) {
        foreach ($d in @($CanonSepidz, $StableSepidz, $Here)) {
            if ($d -and (Test-Path -LiteralPath $d)) { [void]$list.Add($d) }
        }
        $pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
        if (Test-Path -LiteralPath $pub) {
            Get-ChildItem -LiteralPath $pub -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -match '^claude-code-sepidz') {
                    foreach ($w in @((Join-Path $_.FullName 'claude-code\windows'), (Join-Path $_.FullName 'windows'))) {
                        if (Test-Path -LiteralPath $w) { [void]$list.Add($w) }
                    }
                }
            }
        }
    } else {
        foreach ($d in @($CanonSmart, $StableSmart, $Here)) {
            if ($d -and (Test-Path -LiteralPath $d)) { [void]$list.Add($d) }
        }
        $pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
        if (Test-Path -LiteralPath $pub) {
            Get-ChildItem -LiteralPath $pub -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -match '^claude-code-client') {
                    $w = Join-Path $_.FullName 'windows'
                    if (Test-Path -LiteralPath $w) { [void]$list.Add($w) }
                }
            }
        }
    }
    return @($list | Select-Object -Unique)
}

try {
    if ($env:CLAUDE_CONNECT_SKIP_HEAL -eq '1') { exit 0 }

    $hereIsSepidz = Test-IsSepidzClientDir -Dir $Here
    $Canon = if ($hereIsSepidz) { $CanonSepidz } else { $CanonSmart }
    $hereIsCanon = [string]::Equals($Here, $Canon, [StringComparison]::OrdinalIgnoreCase)
    $isLegacyDated = ($Here -match '(?i)claude-code-client-\d{8}') -or ($Here -match '(?i)claude-code-sepidz-\d{8}')
    $isPublishTree = ($Here -match '(?i)[\\/]claude-publish[\\/]')
    $hereGood = Test-GoodClientDir -Dir $Here

    # Sepidz: stay on Sepidz site. Never redirect to Smart Desktop\Claude-Connect.
    if ($hereIsSepidz) {
        if ($hereGood) {
            Write-HealLog ("HEAL_SEPIDZ_STAY here={0} ver={1}" -f $Here, (Get-ClientDirVersion -Dir $Here)) 'INFO'
            exit 0
        }
        $best = $null
        $bestVer = '0'
        foreach ($d in Get-CandidateDirs -ForSepidz:$true) {
            if (-not (Test-GoodClientDir -Dir $d)) { continue }
            if (-not (Test-IsSepidzClientDir -Dir $d)) { continue }
            $v = Get-ClientDirVersion -Dir $d
            if (-not $best) { $best = $d; $bestVer = $v; continue }
            if ((Compare-ClientVersion -A $v -B $bestVer) -gt 0) { $best = $d; $bestVer = $v }
        }
        if ($best -and -not [string]::Equals($best, $Here, [StringComparison]::OrdinalIgnoreCase)) {
            $copied = Copy-ClientFiles -Src $best -Dst $Here
            Write-HealLog ("HEAL_SEPIDZ_HERE from={0} ver={1} files={2}" -f $best, $bestVer, $copied)
        }
        exit 0
    }

    $best = $null
    $bestVer = '0'
    foreach ($d in Get-CandidateDirs -ForSepidz:$false) {
        if (-not (Test-GoodClientDir -Dir $d)) { continue }
        if (Test-IsSepidzClientDir -Dir $d) { continue }
        $v = Get-ClientDirVersion -Dir $d
        if (-not $best) { $best = $d; $bestVer = $v; continue }
        $cmp = Compare-ClientVersion -A $v -B $bestVer
        if ($cmp -gt 0) { $best = $d; $bestVer = $v }
        elseif ($cmp -eq 0 -and [string]::Equals($d, $CanonSmart, [StringComparison]::OrdinalIgnoreCase)) { $best = $d; $bestVer = $v }
    }

    if (-not $best) {
        $boot = $null
        foreach ($c in @((Join-Path $Here 'connect-bootstrap.ps1'), (Join-Path $CanonSmart 'connect-bootstrap.ps1'))) {
            if (Test-Path -LiteralPath $c) { $boot = $c; break }
        }
        if ($boot) {
            Write-HealLog ("HEAL_BOOTSTRAP_PULL via=$boot")
            $bp = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $boot, '-Here', $Here, '-Quiet', '-Force'
            ) -Wait -PassThru -WindowStyle Hidden
            if ($bp -and $bp.ExitCode -eq 2) { exit 2 }
        } else {
            Write-HealLog 'HEAL_NO_SOURCE no local good dir and no connect-bootstrap.ps1' 'ERROR'
        }
    }

    if ($best) {
        $canonGood = Test-GoodClientDir -Dir $CanonSmart
        $canonVer = Get-ClientDirVersion -Dir $CanonSmart
        if (-not $canonGood -or ((Compare-ClientVersion -A $bestVer -B $canonVer) -gt 0)) {
            $copied = Copy-ClientFiles -Src $best -Dst $CanonSmart
            Write-HealLog ("HEAL_CANON from={0} ver={1} files={2}" -f $best, $bestVer, $copied)
        }
    }

    $canonGood = Test-GoodClientDir -Dir $CanonSmart
    if (-not $hereGood -and $canonGood) {
        $copied = Copy-ClientFiles -Src $CanonSmart -Dst $Here
        Write-HealLog ("HEAL_HERE from=Claude-Connect into={0} files={1}" -f $Here, $copied)
        $hereGood = Test-GoodClientDir -Dir $Here
    }

    $shouldRedirect = $false
    if ($canonGood -and -not $hereIsCanon) {
        if ($isLegacyDated -or $isPublishTree) { $shouldRedirect = $true }
        elseif (-not $hereGood) { $shouldRedirect = $true }
    }

    if ($shouldRedirect) {
        Set-Content -LiteralPath $RelaunchMarker -Value $CanonSmart -Encoding ASCII
        Write-HealLog ("HEAL_REDIRECT from={0} to={1} legacy={2} publish={3}" -f $Here, $CanonSmart, $isLegacyDated, $isPublishTree)
        if (-not $Quiet) {
            Write-Host ""
            Write-Host "  [!] Old/publish folder detected - switching to Desktop\Claude-Connect ..." -ForegroundColor Yellow
            Write-Host ""
        }
        exit 2
    }

    exit 0
} catch {
    try { Write-HealLog ("HEAL_FAIL: " + ($_.Exception.Message -replace '[\r\n]', ' ')) 'ERROR' } catch {}
    exit 1
}
