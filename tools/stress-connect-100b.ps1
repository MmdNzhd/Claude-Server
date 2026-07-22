#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Rounds = 100
$BatDir = 'C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$Canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$DeskExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
$HereExe = Join-Path $BatDir 'Claude-Connect.exe'
$Remote = 'smart@192.168.210.240:/usr/local/share/claude-client/Claude-Connect.exe'
$Fail = New-Object System.Collections.Generic.List[string]
$Ok = 0

function Test-Pe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $h = New-Object byte[] 64
        if ($fs.Read($h, 0, 64) -lt 64) { return $false }
        if ($h[0] -ne 0x4D -or $h[1] -ne 0x5A) { return $false }
        $off = [BitConverter]::ToInt32($h, 0x3C)
        if ($off -lt 64 -or $off -gt 1024) { return $false }
        $null = $fs.Seek([int64]$off, [IO.SeekOrigin]::Begin)
        $s = New-Object byte[] 4
        if ($fs.Read($s, 0, 4) -ne 4) { return $false }
        return ($s[0] -eq 0x50 -and $s[1] -eq 0x45 -and $s[2] -eq 0 -and $s[3] -eq 0)
    } finally { $fs.Dispose() }
}

function Get-Sha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Stop-Lockers([string]$Path) {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $cl = [string]$_.CommandLine
        $cl -match 'Claude-Connect\.exe' -or $cl -match 'connect-boot\.ps1' -or $cl -match 'setup-launch' -or $cl -match 'claude-code-client-20260715'
    } | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    # Also stop any process with that path in CommandLine
    $esc = [regex]::Escape($Path)
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ([string]$_.CommandLine) -match $esc
    } | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 300
}

function Copy-Retry([string]$Src, [string]$Dst, [int]$Tries = 8) {
    $parent = Split-Path -Parent $Dst
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Force -Path $parent
    }
    for ($t = 1; $t -le $Tries; $t++) {
        try {
            if (Test-Path -LiteralPath $Dst) {
                Stop-Lockers $Dst
                # write via temp replace
                $tmp = $Dst + '.new'
                Copy-Item -LiteralPath $Src -Destination $tmp -Force -ErrorAction Stop
                Move-Item -LiteralPath $tmp -Destination $Dst -Force -ErrorAction Stop
            } else {
                Copy-Item -LiteralPath $Src -Destination $Dst -Force -ErrorAction Stop
            }
            return
        } catch {
            if ($t -eq $Tries) { throw }
            Stop-Lockers $Dst
            Start-Sleep -Milliseconds (200 * $t)
        }
    }
}

function Fetch-Exe([string]$Dest) {
    $tmp = Join-Path $env:TEMP ("claude-stress-{0}.exe" -f [guid]::NewGuid().ToString('N').Substring(0,8))
    $p = Start-Process -FilePath 'scp' -ArgumentList @(
        '-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-o','IdentitiesOnly=yes','-q',
        $Remote, $tmp
    ) -Wait -PassThru -NoNewWindow
    if ($null -ne $p.ExitCode -and $p.ExitCode -ne 0) { throw ("scp exit={0}" -f $p.ExitCode) }
    if (-not (Test-Pe $tmp)) { throw 'fetched EXE failed PE check' }
    $len = (Get-Item -LiteralPath $tmp).Length
    if ($len -lt 100000) { throw ("fetched EXE too small {0}" -f $len) }
    Copy-Retry $tmp $Dest
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return $len
}

# Pre-clean lockers
Stop-Lockers $HereExe
Stop-Lockers $DeskExe

Write-Host ("STRESS_B begin rounds={0}" -f $Rounds)
$refSha = $null
$refLen = 0

for ($i = 1; $i -le $Rounds; $i++) {
    try {
        $tmpDest = Join-Path $env:TEMP ("claude-round-{0}.exe" -f $i)
        $len = Fetch-Exe $tmpDest
        $sha = Get-Sha $tmpDest
        if ($null -eq $refSha) { $refSha = $sha; $refLen = $len }
        if ($sha -ne $refSha) { throw ("hash drift {0}" -f $i) }
        if ($len -ne $refLen) { throw ("size drift {0}" -f $i) }
        if (-not (Test-Pe $tmpDest)) { throw ("PE fail {0}" -f $i) }

        if (($i % 5) -eq 0) {
            Copy-Retry $tmpDest $HereExe
            Copy-Retry $tmpDest $DeskExe
            $canonExe = Join-Path $Canon 'Claude-Connect.exe'
            Copy-Retry $tmpDest $canonExe
            foreach ($p in @($HereExe, $DeskExe, $canonExe)) {
                if (-not (Test-Pe $p)) { throw ("placed PE fail {0}" -f $p) }
                if ((Get-Sha $p) -ne $refSha) { throw ("placed hash fail {0}" -f $p) }
            }
        }

        if (($i % 25) -eq 0 -and (Test-Path -LiteralPath (Join-Path $BatDir 'connect.bat'))) {
            Stop-Lockers $HereExe
            $bat = Join-Path $BatDir 'connect.bat'
            $null = Start-Process -FilePath $bat -WorkingDirectory $BatDir -PassThru -WindowStyle Minimized
            Start-Sleep -Seconds 6
            Stop-Lockers $HereExe
            if (-not (Test-Pe $HereExe)) {
                [void](Fetch-Exe $HereExe)
                if (-not (Test-Pe $HereExe)) { throw ("refetch still bad {0}" -f $i) }
            }
            if (-not (Test-Pe $DeskExe)) { throw ("desk broken {0}" -f $i) }
        }

        Remove-Item -LiteralPath $tmpDest -Force -ErrorAction SilentlyContinue
        $Ok++
        if (($i % 10) -eq 0) { Write-Host ("  ok {0}/{1}" -f $i, $Rounds) }
    } catch {
        $msg = ("FAIL round={0} {1}" -f $i, $_.Exception.Message)
        $Fail.Add($msg) | Out-Null
        Write-Host $msg -ForegroundColor Red
        try {
            Stop-Lockers $HereExe
            [void](Fetch-Exe $HereExe)
            [void](Fetch-Exe $DeskExe)
            [void](Fetch-Exe (Join-Path $Canon 'Claude-Connect.exe'))
        } catch {
            Write-Host ("heal-failed {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host '==== SUMMARY ===='
Write-Host ("passed={0}/{1}" -f $Ok, $Rounds)
Write-Host ("failed={0}" -f $Fail.Count)
Write-Host ("ref_sha={0}" -f $refSha)
Write-Host ("ref_len={0}" -f $refLen)
Write-Host ("here_pe={0}" -f (Test-Pe $HereExe))
Write-Host ("desk_pe={0}" -f (Test-Pe $DeskExe))
Write-Host ("canon_pe={0}" -f (Test-Pe (Join-Path $Canon 'Claude-Connect.exe')))
if ($Fail.Count -gt 0) { $Fail | Select-Object -First 10 | ForEach-Object { Write-Host $_ }; exit 1 }
Write-Host 'VERDICT=PASS_100'
exit 0
