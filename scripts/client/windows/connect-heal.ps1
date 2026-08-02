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

$_connectEnvRepair = Join-Path $(if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }) 'connect-env-repair.ps1'
if (Test-Path -LiteralPath $_connectEnvRepair) {
    . $_connectEnvRepair
} else {
    # Inline fallback when ancient folders lack connect-env-repair.ps1 (Parsa 8.3).
    try {
        $longProfile = $null
        try {
            $fp = [Environment]::GetFolderPath('UserProfile')
            if ($fp -and ($fp -notmatch '~') -and (Test-Path -LiteralPath $fp)) { $longProfile = $fp }
        } catch {}
        if (-not $longProfile) {
            $u = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
            if ($u -and ($u -notmatch '~')) {
                $guess = Join-Path 'C:\Users' $u
                if (Test-Path -LiteralPath $guess) { $longProfile = $guess }
            }
        }
        if ($longProfile -and ($longProfile -notmatch '~') -and (Test-Path -LiteralPath $longProfile)) {
            if (-not $env:USERPROFILE -or ($env:USERPROFILE -match '~') -or -not (Test-Path -LiteralPath $env:USERPROFILE)) {
                $env:USERPROFILE = $longProfile
            }
            $longLocal = Join-Path $longProfile 'AppData\Local'
            if ((Test-Path -LiteralPath $longLocal) -and (
                    -not $env:LOCALAPPDATA -or ($env:LOCALAPPDATA -match '~') -or -not (Test-Path -LiteralPath $env:LOCALAPPDATA))) {
                $env:LOCALAPPDATA = $longLocal
            }
        }
    } catch {}
    try {
        $tempCandidates = New-Object System.Collections.Generic.List[string]
        if ($env:LOCALAPPDATA -and ($env:LOCALAPPDATA -notmatch '~')) {
            [void]$tempCandidates.Add((Join-Path $env:LOCALAPPDATA 'Temp'))
        }
        if ($env:USERPROFILE -and ($env:USERPROFILE -notmatch '~')) {
            [void]$tempCandidates.Add((Join-Path $env:USERPROFILE 'AppData\Local\Temp'))
        }
        try {
            $p = [IO.Path]::GetTempPath()
            if ($p -and ($p -notmatch '~')) { [void]$tempCandidates.Add($p) }
        } catch {}
        if ($env:TEMP -and ($env:TEMP -notmatch '~')) { [void]$tempCandidates.Add($env:TEMP) }
        if ($env:TMP -and ($env:TMP -notmatch '~')) { [void]$tempCandidates.Add($env:TMP) }
        if ($env:SystemRoot) { [void]$tempCandidates.Add((Join-Path $env:SystemRoot 'Temp')) }
        foreach ($cand in $tempCandidates) {
            if (-not $cand -or ($cand -match '~')) { continue }
            try {
                if (-not (Test-Path -LiteralPath $cand)) {
                    New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
                }
                $full = (Get-Item -LiteralPath $cand -ErrorAction Stop).FullName
                if ($full -and ($full -notmatch '~')) { $env:TEMP = $full; $env:TMP = $full; break }
            } catch { continue }
        }
    } catch {}
}
$_connectEnvRepair = $null

$Here = $Here.TrimEnd('\', '/')
$CanonSmart = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$CanonSepidz = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Sepidz'
$StableSmart = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client\windows'
$StableSepidz = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz\claude-code\windows'
$RelaunchMarker = Join-Path $env:TEMP 'claude-connect-relaunch.dir'

$Essential = @(
    'connect.bat',
    'connect-hide-relaunch.vbs',
    'connect-hide-console.ps1',
    'connect-boot.ps1',
    'connect-heal.ps1',
    'connect-bootstrap.ps1',
    'connect-preflight.ps1',
    'connect-env-repair.ps1',
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

function Resolve-VersionedSrcUnderRoot {
    # Desktop\Claude-Connect\{ver}\src when versioned layout is in use.
    param([string]$Root)
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
    if ((Split-Path -Leaf $Root) -ne 'Claude-Connect') { return $null }
    $ver = ''
    if (Get-Command Get-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
        $ver = Get-ConnectInstallCurrent -Root $Root
    }
    if ($ver -notmatch '^\d{8}\.\d+$') {
        try {
            $cf = Join-Path $Root 'current.txt'
            if (Test-Path -LiteralPath $cf) {
                $ver = (Get-Content -LiteralPath $cf -Raw -ErrorAction SilentlyContinue).Trim()
            }
        } catch { $ver = '' }
    }
    if ($ver -notmatch '^\d{8}\.\d+$') {
        Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
            Sort-Object Name -Descending |
            Select-Object -First 1 |
            ForEach-Object { $ver = $_.Name }
    }
    if ($ver -notmatch '^\d{8}\.\d+$') { return $null }
    $src = Join-Path $Root (Join-Path $ver 'src')
    if (Test-Path -LiteralPath (Join-Path $src 'connect.ps1')) { return $src }
    return $src
}

function Test-GoodClientDir {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    if (-not (Test-Path -LiteralPath $Dir)) { return $false }
    # Versioned Claude-Connect root: judge by {ver}\src, not flat root dump.
    if ((Split-Path -Leaf $Dir) -eq 'Claude-Connect') {
        $vs = Resolve-VersionedSrcUnderRoot -Root $Dir
        if ($vs -and (Test-Path -LiteralPath (Join-Path $vs 'connect.ps1'))) {
            return (Test-GoodClientDir -Dir $vs)
        }
    }
    foreach ($n in @('connect.bat', 'connect.ps1', 'connect-update.ps1', 'cursor-proxy-sidecar.ps1', 'connect-version.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir $n))) { return $false }
    }
    foreach ($n in @('connect-diagnostic.ps1', 'connect-ui.ps1')) {
        $fp = Join-Path $Dir $n
        if ((Test-Path -LiteralPath $fp) -and (Test-IsStaleShadowClientFile -Path $fp)) { return $false }
    }
    try {
        $raw = Get-Content -LiteralPath (Join-Path $Dir 'connect-update.ps1') -Raw -ErrorAction Stop
        if ($raw -match 'UpdateEndpointTarget') { return $false }
    } catch { return $false }
    return $true
}

function Test-IsStaleShadowClientFile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $head = Get-Content -LiteralPath $Path -TotalCount 5 -ErrorAction Stop | Out-String
        return ($head -match 'STALE-SHADOW REPLACED')
    } catch { return $false }
}

function Copy-ClientFiles {
    param([string]$Src, [string]$Dst)
    # Never dump a flat script tree onto Desktop\Claude-Connect root when versioned layout exists.
    if ($Dst -and (Split-Path -Leaf $Dst) -eq 'Claude-Connect') {
        $vs = Resolve-VersionedSrcUnderRoot -Root $Dst
        if ($vs) { $Dst = $vs }
        else {
            # No versioned src yet — refuse flat root dump (folders-only contract).
            Write-HealLog ("HEAL_REFUSE_FLAT_ROOT dst=$Dst") 'WARN'
            return 0
        }
    }
    New-Item -ItemType Directory -Force -Path $Dst | Out-Null
    $n = 0
    foreach ($name in $Essential) {
        $s = Join-Path $Src $name
        if (-not (Test-Path -LiteralPath $s)) { continue }
        # Never copy repo windows/ STALE-SHADOW wrappers into a live install.
        if (Test-IsStaleShadowClientFile -Path $s) {
            Write-HealLog ("HEAL_SKIP_SHADOW file=$name from=$Src") 'WARN'
            continue
        }
        $dest = Join-Path $Dst $name
        if ((Test-Path -LiteralPath $dest) -and -not (Test-IsStaleShadowClientFile -Path $dest)) {
            # Keep existing canon; do not overwrite with unknown smaller junk.
            $srcLen = (Get-Item -LiteralPath $s).Length
            $dstLen = (Get-Item -LiteralPath $dest).Length
            if ($dstLen -gt 2000 -and $srcLen -lt [Math]::Max(500, [int]($dstLen * 0.25))) { continue }
        }
        Copy-Item -LiteralPath $s -Destination $dest -Force
        $n++
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
        $vs = Resolve-VersionedSrcUnderRoot -Root $CanonSmart
        if ($vs -and (Test-Path -LiteralPath $vs)) { [void]$list.Add($vs) }
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
    # Portable/manually-extracted runner left in Downloads\Claude-Connect\{ver}\ (or any
    # Downloads subtree). Heal only ever writes the canonical Desktop tree, so a running
    # process launched from a stale Downloads copy never sees pushed updates on its own -
    # it must be detected here and handed off. See docs/connect-fix-evidence/
    # FLEET-PROBLEMS-20260801.md "Product debt" (2026-08-01).
    $isUnderDownloads = ($Here -match '(?i)[\\/]Downloads[\\/]')
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
        $canonScript = Resolve-VersionedSrcUnderRoot -Root $CanonSmart
        if (-not $canonScript) { $canonScript = $CanonSmart }
        $canonGood = Test-GoodClientDir -Dir $canonScript
        $canonVer = Get-ClientDirVersion -Dir $canonScript
        if (-not $canonGood -or ((Compare-ClientVersion -A $bestVer -B $canonVer) -gt 0)) {
            $copied = Copy-ClientFiles -Src $best -Dst $canonScript
            Write-HealLog ("HEAL_CANON from={0} ver={1} files={2} dst={3}" -f $best, $bestVer, $copied, $canonScript)
        }
    }

    $canonScript = Resolve-VersionedSrcUnderRoot -Root $CanonSmart
    if (-not $canonScript) { $canonScript = $CanonSmart }
    $canonGood = Test-GoodClientDir -Dir $canonScript
    if (-not $hereGood -and $canonGood) {
        $copied = Copy-ClientFiles -Src $canonScript -Dst $Here
        Write-HealLog ("HEAL_HERE from={0} into={1} files={2}" -f $canonScript, $Here, $copied)
        $hereGood = Test-GoodClientDir -Dir $Here
    }

    # Keep Desktop\Claude-Connect root = version folders + launchers only.
    if (Get-Command Repair-ConnectRootLayout -ErrorAction SilentlyContinue) {
        try {
            $cv = ''
            try {
                $cv = (Get-Content -LiteralPath (Join-Path $CanonSmart 'current.txt') -Raw -ErrorAction SilentlyContinue).Trim()
            } catch { $cv = '' }
            [void](Repair-ConnectRootLayout -Root $CanonSmart -Ver $cv)
            Write-HealLog 'HEAL_ROOT_LAYOUT ok' 'INFO'
        } catch {
            Write-HealLog ("HEAL_ROOT_LAYOUT_WARN " + ($_.Exception.Message -replace '[\r\n]', ' ')) 'WARN'
        }
    }

    # Downloads runner older than the canonical Desktop install: heal/push (Task 6 /
    # deploy-client-bundle) only ever writes Desktop\Claude-Connect, so a process still
    # running out of a portable Downloads\Claude-Connect\{oldver}\ tree would otherwise
    # stay on the old version forever. Force handoff once canon is strictly newer.
    $downloadsStale = $false
    $hereVer = '0'
    $canonVerNow = '0'
    if ($isUnderDownloads -and $canonGood -and -not $hereIsCanon) {
        $hereVer = Get-ClientDirVersion -Dir $Here
        $canonVerNow = Get-ClientDirVersion -Dir $canonScript
        if ((Compare-ClientVersion -A $hereVer -B $canonVerNow) -lt 0) { $downloadsStale = $true }
    }

    $shouldRedirect = $false
    if ($canonGood -and -not $hereIsCanon) {
        if ($isLegacyDated -or $isPublishTree) { $shouldRedirect = $true }
        elseif (-not $hereGood) { $shouldRedirect = $true }
        elseif ($downloadsStale) { $shouldRedirect = $true }
    }

    if ($shouldRedirect) {
        Set-Content -LiteralPath $RelaunchMarker -Value $CanonSmart -Encoding ASCII
        Write-HealLog ("HEAL_REDIRECT from={0} to={1} legacy={2} publish={3} downloads_stale={4} here_ver={5} canon_ver={6}" -f $Here, $CanonSmart, $isLegacyDated, $isPublishTree, $downloadsStale, $hereVer, $canonVerNow)
        if (-not $Quiet) {
            Write-Host ""
            if ($downloadsStale) {
                Write-Host "  [!] Older Downloads copy detected (ver=$hereVer < $canonVerNow) - switching to Desktop\Claude-Connect ..." -ForegroundColor Yellow
            } else {
                Write-Host "  [!] Old/publish folder detected - switching to Desktop\Claude-Connect ..." -ForegroundColor Yellow
            }
            Write-Host ""
        }
        exit 2
    }

    exit 0
} catch {
    try { Write-HealLog ("HEAL_FAIL: " + ($_.Exception.Message -replace '[\r\n]', ' ')) 'ERROR' } catch {}
    exit 1
}
