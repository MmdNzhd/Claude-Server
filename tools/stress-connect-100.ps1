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
    $fs = [IO.File]::OpenRead($Path)
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
    $parent = Split-Path -Parent $Dest
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Force -Path $parent }
    Copy-Item -LiteralPath $tmp -Destination $Dest -Force
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return $len
}

Write-Host ("STRESS begin rounds={0}" -f $Rounds)
$refSha = $null
$refLen = 0

for ($i = 1; $i -le $Rounds; $i++) {
    try {
        # Round pattern:
        # - every round: refetch to temp + PE + size stable
        # - every 5th: place into Downloads windows + Desktop + Canon and PE all three
        # - every 20th: launch connect.bat briefly and ensure no BAD PE after
        $tmpDest = Join-Path $env:TEMP ("claude-round-{0}.exe" -f $i)
        $len = Fetch-Exe $tmpDest
        $sha = Get-Sha $tmpDest
        if ($null -eq $refSha) { $refSha = $sha; $refLen = $len }
        if ($sha -ne $refSha) { throw ("hash drift round {0}: {1} vs {2}" -f $i, $sha, $refSha) }
        if ($len -ne $refLen) { throw ("size drift round {0}: {1} vs {2}" -f $i, $len, $refLen) }
        if (-not (Test-Pe $tmpDest)) { throw ("PE fail round {0}" -f $i) }

        if (($i % 5) -eq 0) {
            Copy-Item -LiteralPath $tmpDest -Destination $HereExe -Force
            Copy-Item -LiteralPath $tmpDest -Destination $DeskExe -Force
            $canonExe = Join-Path $Canon 'Claude-Connect.exe'
            if (-not (Test-Path -LiteralPath $Canon)) { $null = New-Item -ItemType Directory -Force -Path $Canon }
            Copy-Item -LiteralPath $tmpDest -Destination $canonExe -Force
            foreach ($p in @($HereExe, $DeskExe, $canonExe)) {
                if (-not (Test-Pe $p)) { throw ("placed PE fail {0}" -f $p) }
                if ((Get-Sha $p) -ne $refSha) { throw ("placed hash fail {0}" -f $p) }
            }
        }

        if (($i % 20) -eq 0 -and (Test-Path -LiteralPath (Join-Path $BatDir 'connect.bat'))) {
            # Kill prior boots
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
                $cl = [string]$_.CommandLine
                $cl -match 'connect-boot\.ps1'
            } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Milliseconds 400
            $bat = Join-Path $BatDir 'connect.bat'
            $proc = Start-Process -FilePath $bat -WorkingDirectory $BatDir -PassThru -WindowStyle Minimized
            Start-Sleep -Seconds 8
            # Ensure EXE still valid after bat activity
            if (Test-Path -LiteralPath $HereExe) {
                if (-not (Test-Pe $HereExe)) { throw ("after-bat PE broken round {0}" -f $i) }
            } else {
                # If missing, refetch into place (user asked)
                [void](Fetch-Exe $HereExe)
                if (-not (Test-Pe $HereExe)) { throw ("refetch after missing still bad round {0}" -f $i) }
            }
            if (-not (Test-Pe $DeskExe)) { throw ("desk PE broken round {0}" -f $i) }
            # stop boot if started
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
                $cl = [string]$_.CommandLine
                $cl -match 'connect-boot\.ps1'
            } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        }

        Remove-Item -LiteralPath $tmpDest -Force -ErrorAction SilentlyContinue
        $Ok++
        if (($i % 10) -eq 0) { Write-Host ("  ok {0}/{1} sha={2} len={3}" -f $i, $Rounds, $refSha.Substring(0,12), $refLen) }
    } catch {
        $msg = ("FAIL round={0} {1}" -f $i, $_.Exception.Message)
        $Fail.Add($msg) | Out-Null
        Write-Host $msg -ForegroundColor Red
        # self-heal attempt then continue
        try {
            [void](Fetch-Exe $HereExe)
            [void](Fetch-Exe $DeskExe)
            [void](Fetch-Exe (Join-Path $Canon 'Claude-Connect.exe'))
        } catch {
            Write-Host ("heal-also-failed {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host '==== SUMMARY ===='
Write-Host ("passed={0}/{1}" -f $Ok, $Rounds)
Write-Host ("failed={0}" -f $Fail.Count)
Write-Host ("ref_sha={0}" -f $refSha)
Write-Host ("ref_len={0}" -f $refLen)
Write-Host ("here={0} pe={1}" -f $HereExe, (Test-Pe $HereExe))
Write-Host ("desk={0} pe={1}" -f $DeskExe, (Test-Pe $DeskExe))
Write-Host ("canon pe={0}" -f (Test-Pe (Join-Path $Canon 'Claude-Connect.exe')))
if ($Fail.Count -gt 0) {
    Write-Host 'failures:'
    $Fail | Select-Object -First 20 | ForEach-Object { Write-Host ("  {0}" -f $_) }
    exit 1
}
Write-Host 'VERDICT=PASS_100'
exit 0
