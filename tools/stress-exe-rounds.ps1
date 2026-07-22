#Requires -Version 5.1
param([int]$Rounds = 50, [int]$ScpRetries = 4)
$ErrorActionPreference = 'Stop'
$Server = 'smart@192.168.210.240'
$RemoteExe = '/usr/local/share/claude-client/Claude-Connect.exe'
$RemoteVer = '/usr/local/share/claude-client/connect-version.txt'
$DeskExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
$CanonExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
$OldDir = 'C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$OldExe = Join-Path $OldDir 'Claude-Connect.exe'
$Fail = New-Object System.Collections.Generic.List[string]
$Pass = 0
$ScpFlakes = 0

function Test-Pe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @{ Ok = $false; Why = 'missing'; Len = 0; Hash = '' } }
    $len = [int64](Get-Item -LiteralPath $Path).Length
    $fs = [IO.File]::OpenRead($Path)
    try {
        $h = New-Object byte[] 64
        if ($fs.Read($h, 0, 64) -lt 64) { return @{ Ok = $false; Why = 'short'; Len = $len; Hash = '' } }
        if ($h[0] -ne 0x4D -or $h[1] -ne 0x5A) { return @{ Ok = $false; Why = 'noMZ'; Len = $len; Hash = '' } }
        $off = [BitConverter]::ToInt32($h, 0x3C)
        if ($off -lt 64 -or $off -gt 1024) { return @{ Ok = $false; Why = 'badOff'; Len = $len; Hash = '' } }
        $null = $fs.Seek([int64]$off, [IO.SeekOrigin]::Begin)
        $s = New-Object byte[] 4
        if ($fs.Read($s, 0, 4) -ne 4) { return @{ Ok = $false; Why = 'nosig'; Len = $len; Hash = '' } }
        $ok = ($s[0] -eq 0x50 -and $s[1] -eq 0x45 -and $s[2] -eq 0 -and $s[3] -eq 0)
        $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        return @{ Ok = $ok; Why = $(if ($ok) { 'PE' } else { 'badPE' }); Len = $len; Hash = $hash }
    } finally { $fs.Dispose() }
}


function Copy-Retry([string]$Src, [string]$Dst, [int]$Tries = 8) {
    $dir = Split-Path -Parent $Dst
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    for ($i = 1; $i -le $Tries; $i++) {
        try {
            Copy-Item -LiteralPath $Src -Destination $Dst -Force -ErrorAction Stop
            return
        } catch {
            if ($i -ge $Tries) { throw }
            Start-Sleep -Milliseconds (150 * $i)
        }
    }
}

function Invoke-ScpRetry([string]$RemotePath, [string]$LocalPath, [int]$TimeoutSec = 45) {
    $script:ScpFlakes = $script:ScpFlakes
    for ($i = 1; $i -le $ScpRetries; $i++) {
        Remove-Item -LiteralPath $LocalPath -Force -ErrorAction SilentlyContinue
        $p = Start-Process -FilePath 'scp' -ArgumentList @(
            '-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ConnectionAttempts=1',
            '-o','ControlMaster=no','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','-q',
            "${Server}:${RemotePath}", $LocalPath
        ) -Wait -PassThru -NoNewWindow
        $ec = -1
        if ($p -and $null -ne $p.ExitCode) { $ec = [int]$p.ExitCode }
        if ($ec -eq 0 -and (Test-Path -LiteralPath $LocalPath)) { return }
        if ($i -lt $ScpRetries) {
            $script:ScpFlakes++
            Start-Sleep -Seconds (1 * $i)
        } else {
            throw "scp fail path=$RemotePath exit=$ec after $ScpRetries tries"
        }
    }
}

function Get-RemoteMeta {
    $tmpV = Join-Path $env:TEMP ("claude-stress-ver-{0}.txt" -f ([guid]::NewGuid().ToString('N').Substring(0,8)))
    $tmpE = Join-Path $env:TEMP ("claude-stress-exe-{0}.exe" -f ([guid]::NewGuid().ToString('N').Substring(0,8)))
    Invoke-ScpRetry -RemotePath $RemoteVer -LocalPath $tmpV
    $ver = ((Get-Content -LiteralPath $tmpV -Raw) + '').Trim()
    Invoke-ScpRetry -RemotePath $RemoteExe -LocalPath $tmpE
    $pe = Test-Pe $tmpE
    if (-not $pe.Ok) { throw "remote download not PE: $($pe.Why) len=$($pe.Len)" }
    if ($pe.Len -lt 100000) { throw "remote exe too small $($pe.Len)" }
    Remove-Item -LiteralPath $tmpV -Force -ErrorAction SilentlyContinue
    return @{ Ver = $ver; Path = $tmpE; Pe = $pe }
}

Write-Host ("STRESS start rounds={0} scpRetries={1}" -f $Rounds, $ScpRetries)
$baseline = Get-RemoteMeta
Write-Host ("baseline ver={0} len={1} sha={2}" -f $baseline.Ver, $baseline.Pe.Len, $baseline.Pe.Hash.Substring(0,16))

for ($r = 1; $r -le $Rounds; $r++) {
    try {
        $meta = Get-RemoteMeta
        if ($meta.Ver -ne $baseline.Ver) { throw "version drift $($meta.Ver) vs $($baseline.Ver)" }
        if ($meta.Pe.Hash -ne $baseline.Pe.Hash) { throw "hash drift" }
        if ($meta.Pe.Len -ne $baseline.Pe.Len) { throw "size drift" }

        if (($r % 5) -eq 1) {
            if (-not (Test-Path -LiteralPath $OldDir)) { New-Item -ItemType Directory -Force -Path $OldDir | Out-Null }
            Copy-Retry $meta.Path $OldExe
            Copy-Retry $meta.Path $DeskExe
            $canonDir = Split-Path $CanonExe -Parent
            if (-not (Test-Path $canonDir)) { New-Item -ItemType Directory -Force -Path $canonDir | Out-Null }
            Copy-Retry $meta.Path $CanonExe
        }

        foreach ($pair in @(
            @{ N = 'download'; P = $meta.Path },
            @{ N = 'desk'; P = $DeskExe },
            @{ N = 'canon'; P = $CanonExe },
            @{ N = 'old'; P = $OldExe }
        )) {
            $pe = Test-Pe $pair.P
            if (-not $pe.Ok) { throw "$($pair.N) PE fail $($pe.Why)" }
            if ($pe.Hash -ne $baseline.Pe.Hash) { throw "$($pair.N) hash mismatch" }
            if ($pe.Len -ne $baseline.Pe.Len) { throw "$($pair.N) size mismatch" }
        }

        $Pass++
        if (($r % 10) -eq 0 -or $r -eq 1 -or $r -eq $Rounds) {
            Write-Host ("OK round={0}/{1}" -f $r, $Rounds)
        }
        Remove-Item -LiteralPath $meta.Path -Force -ErrorAction SilentlyContinue
    } catch {
        $msg = "FAIL round=$r :: $($_.Exception.Message)"
        [void]$Fail.Add($msg)
        Write-Host $msg -ForegroundColor Red
        try {
            $fix = Get-RemoteMeta
            Copy-Retry $fix.Path $DeskExe
            Copy-Retry $fix.Path $CanonExe
            if (-not (Test-Path $OldDir)) { New-Item -ItemType Directory -Force -Path $OldDir | Out-Null }
            Copy-Retry $fix.Path $OldExe
            Write-Host ("repaired round={0}" -f $r) -ForegroundColor Yellow
            Remove-Item -LiteralPath $fix.Path -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host ("repair failed: $($_.Exception.Message)") -ForegroundColor Red
        }
    }
}

Write-Host ''
Write-Host ("SUMMARY pass={0} fail={1} scp_flakes_recovered={2} rounds={3}" -f $Pass, $Fail.Count, $ScpFlakes, $Rounds)
Write-Host ("final desk={0} canon={1} old={2}" -f (Test-Pe $DeskExe).Why, (Test-Pe $CanonExe).Why, (Test-Pe $OldExe).Why)
if ($Fail.Count -gt 0) { $Fail | ForEach-Object { Write-Host $_ }; exit 1 }
Write-Host 'ALL_ROUNDS_GREEN'
exit 0
