# -*- coding: utf-8 -*-
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')
upd = root / 'scripts/client/windows/connect-update.ps1'
build = root / 'publish/build-windows-exe.ps1'

text = upd.read_text(encoding='utf-8')

NEW_FUNCS = r'''
function Get-LocalConnectExePath {
    $candidates = @(
        (Join-Path $ScriptDir 'Claude-Connect.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Setup.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-RemoteExeShaFromChecksums {
    param([string]$ChecksumText)
    foreach ($line in ($ChecksumText -split '\r?\n')) {
        $trim = ($line + '').Trim()
        if (-not $trim -or $trim.StartsWith('#')) { continue }
        if ($trim -notmatch '^(?i)([a-f0-9]{64})\s+\*?(.+)$') { continue }
        $rel = ($Matches[2] -replace '\\', '/').Trim().TrimStart('./')
        if ($rel -eq 'Claude-Connect.exe' -or $rel.EndsWith('/Claude-Connect.exe')) {
            return $Matches[1].ToLowerInvariant()
        }
    }
    return $null
}

function Test-LocalExeMatchesRemoteHash {
    # $true = match, $false = mismatch/missing, $null = no EXE on server checksums
    param([string]$ChecksumText)
    $want = Get-RemoteExeShaFromChecksums -ChecksumText $ChecksumText
    if (-not $want) { return $null }
    $local = Get-LocalConnectExePath
    if (-not $local) {
        Write-UpdateFileLog 'local_exe_missing drift=1'
        return $false
    }
    $got = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -ne $want) {
        Write-UpdateFileLog ("local_exe_drift local=$local") 'WARN'
        return $false
    }
    Write-UpdateFileLog ("local_exe_ok path=$local")
    return $true
}

function Test-RemoteExePresent {
    param([string]$Target)
    $cmd = "test -f `"$RemoteBundle/Claude-Connect.exe`" && echo OK || echo NO"
    $r = Invoke-SshTimed -ArgumentList ($script:SshCommonOpts + @($Target, $cmd)) -TimeoutMs 10000
    if (-not $r.Ok) { return $false }
    $out = ''
    if ($r.ContainsKey('Out')) { $out = [string]$r.Out }
    return ($out -match 'OK')
}

function Invoke-ExeOnlyClientUpdate {
    # Download ONLY Claude-Connect.exe, extract into Desktop\Claude-Connect (no second UI),
    # sync files into the live ScriptDir, promote Desktop EXE, then caller exits 2.
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$RemoteVer
    )
    if (-not (Test-RemoteExePresent -Target $Target)) {
        Write-UpdateFileLog 'exe_only_skip remote_exe_missing'
        return $false
    }

    $tmpDir = Join-Path $env:TEMP ("claude-connect-exe-upd-{0}" -f $PID)
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Force -Path $tmpDir
    $tmpExe = Join-Path $tmpDir 'Claude-Connect.exe'

    Write-UpdateMsg '  downloading Claude-Connect.exe...' 'DarkGray'
    Write-UpdateFileLog ("exe_only_scp begin target=$Target")
    $scpOpts = @(
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=20',
        '-o', 'ConnectionAttempts=1',
        '-o', 'ControlMaster=no',
        '-o', 'IdentitiesOnly=yes',
        '-o', 'IdentityAgent=none',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-q',
        "${Target}:${RemoteBundle}/Claude-Connect.exe",
        $tmpExe
    )
    $r = Invoke-SshTimed -Exe 'scp' -ArgumentList $scpOpts -TimeoutMs 180000
    if (-not $r.Ok -or -not (Test-Path -LiteralPath $tmpExe)) {
        Write-UpdateFileLog 'exe_only_scp_fail' 'ERROR'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    $len = (Get-Item -LiteralPath $tmpExe).Length
    if ($len -lt 10000) {
        Write-UpdateFileLog ("exe_only_too_small bytes=$len") 'ERROR'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    Write-UpdateFileLog ("exe_only_scp_ok bytes=$len")

    $canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
    Write-UpdateMsg '  installing from EXE (files only)...' 'DarkGray'
    $prevNoLaunch = $env:CLAUDE_CONNECT_SETUP_NO_LAUNCH
    $env:CLAUDE_CONNECT_SETUP_NO_LAUNCH = '1'
    try {
        $p = Start-Process -FilePath $tmpExe -WorkingDirectory $tmpDir -Wait -PassThru -WindowStyle Hidden
        $ec = 0
        if ($p -and $null -ne $p.ExitCode) { $ec = [int]$p.ExitCode }
        if ($ec -ne 0) {
            Write-UpdateFileLog ("exe_only_setup_fail exit=$ec") 'ERROR'
            return $false
        }
    } finally {
        if ($null -eq $prevNoLaunch -or $prevNoLaunch -eq '') {
            Remove-Item Env:\CLAUDE_CONNECT_SETUP_NO_LAUNCH -ErrorAction SilentlyContinue
        } else {
            $env:CLAUDE_CONNECT_SETUP_NO_LAUNCH = $prevNoLaunch
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $canon 'connect.bat'))) {
        Write-UpdateFileLog 'exe_only_canon_missing_after_setup' 'ERROR'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # Always place the NEW downloaded EXE on Desktop + inside install folder.
    $deskExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
    $deskSetup = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Setup.exe'
    $canonExe = Join-Path $canon 'Claude-Connect.exe'
    Copy-Item -LiteralPath $tmpExe -Destination $deskExe -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $tmpExe -Destination $deskSetup -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $tmpExe -Destination $canonExe -Force -ErrorAction SilentlyContinue

    # If user launched from another folder (old bat), refresh that folder too.
    $liveWin = $ScriptDir
    $leaf = Split-Path -Leaf $ScriptDir
    if ($leaf -eq 'windows') { $liveWin = $ScriptDir }
    elseif (Test-Path (Join-Path $ScriptDir 'connect.bat')) { $liveWin = $ScriptDir }
    try {
        $canonFull = [IO.Path]::GetFullPath($canon)
        $liveFull = [IO.Path]::GetFullPath($liveWin)
    } catch {
        $canonFull = $canon
        $liveFull = $liveWin
    }
    if ($liveFull -and ($liveFull -ne $canonFull) -and (Test-Path -LiteralPath $liveWin)) {
        Write-UpdateFileLog ("exe_only_sync_live live=$liveWin")
        Get-ChildItem -LiteralPath $canon -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^(setup-claude-connect\.cmd|setup-launch\.ps1|READ-ME-USERS\.txt)$') { return }
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $liveWin $_.Name) -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $tmpExe -Destination (Join-Path $liveWin 'Claude-Connect.exe') -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-UpdateFileLog ("exe_only_applied ok ver=$RemoteVer")
    return $true
}

function Ship-UpdateDayLogChunk {
'''

# Insert new funcs before Invoke-BundleDownload
marker = 'function Invoke-BundleDownload {'
if 'function Invoke-ExeOnlyClientUpdate {' in text:
    print('connect-update already has Invoke-ExeOnlyClientUpdate')
else:
    if marker not in text:
        raise SystemExit('marker Invoke-BundleDownload not found')
    text = text.replace(marker, NEW_FUNCS + '\n' + marker, 1)
    print('inserted EXE-only helpers')

# Fix Ship-UpdateDayLogChunk stub - I accidentally left incomplete function.
# Remove the broken stub and put ship logic only at call site.
text = text.replace(
    'function Ship-UpdateDayLogChunk {\n\nfunction Invoke-BundleDownload {',
    'function Invoke-BundleDownload {',
    1,
)

# Replace content-drift block to prefer EXE hash
old_drift = '''$versionNewer = [bool](Test-RemoteVersionNewer -Remote $remoteVer -Local $localVer)
$contentDrift = $false
if (-not $versionNewer) {
    # Same version string can still mean corrupt/partial local files - verify against server.
    $remoteSums = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/checksums.txt"
    if ($remoteSums) {
        $leafGate = Split-Path -Leaf $ScriptDir
        $winDirGate = $ScriptDir
        $pkgGate = $ScriptDir
        if ($leafGate -eq 'windows') {
            $pkgGate = Split-Path -Parent $ScriptDir
            $winDirGate = $ScriptDir
        } elseif (Test-Path (Join-Path $ScriptDir 'windows')) {
            $winDirGate = Join-Path $ScriptDir 'windows'
            $pkgGate = $ScriptDir
        }
        $macDirGate = Join-Path $pkgGate 'mac'
        if (-not (Test-Path -LiteralPath $macDirGate)) { $macDirGate = '' }
        if (-not (Test-LocalMatchesRemoteChecksums -ChecksumText $remoteSums -WindowsDir $winDirGate -MacDir $macDirGate)) {
            $contentDrift = $true
        }
    } else {
        Write-UpdateFileLog 'local_checksum_skip remote_checksums_unreachable' 'WARN'
    }
}'''

new_drift = '''$versionNewer = [bool](Test-RemoteVersionNewer -Remote $remoteVer -Local $localVer)
$contentDrift = $false
if (-not $versionNewer) {
    # Prefer EXE-only drift check: if server ships Claude-Connect.exe, only that hash matters.
    $remoteSums = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/checksums.txt"
    if ($remoteSums) {
        $exeMatch = Test-LocalExeMatchesRemoteHash -ChecksumText $remoteSums
        if ($exeMatch -eq $true) {
            $contentDrift = $false
            Write-UpdateFileLog 'drift_gate=exe_ok'
        } elseif ($exeMatch -eq $false) {
            $contentDrift = $true
            Write-UpdateFileLog 'drift_gate=exe_mismatch'
        } else {
            # No EXE in remote checksums - legacy full-file compare.
            $leafGate = Split-Path -Leaf $ScriptDir
            $winDirGate = $ScriptDir
            $pkgGate = $ScriptDir
            if ($leafGate -eq 'windows') {
                $pkgGate = Split-Path -Parent $ScriptDir
                $winDirGate = $ScriptDir
            } elseif (Test-Path (Join-Path $ScriptDir 'windows')) {
                $winDirGate = Join-Path $ScriptDir 'windows'
                $pkgGate = $ScriptDir
            }
            $macDirGate = Join-Path $pkgGate 'mac'
            if (-not (Test-Path -LiteralPath $macDirGate)) { $macDirGate = '' }
            if (-not (Test-LocalMatchesRemoteChecksums -ChecksumText $remoteSums -WindowsDir $winDirGate -MacDir $macDirGate)) {
                $contentDrift = $true
            }
        }
    } else {
        Write-UpdateFileLog 'local_checksum_skip remote_checksums_unreachable' 'WARN'
    }
}'''

if old_drift not in text:
    if 'drift_gate=exe_ok' in text:
        print('drift block already patched')
    else:
        raise SystemExit('drift block not found for replace')
else:
    text = text.replace(old_drift, new_drift, 1)
    print('patched drift gate')

# Replace apply section: from $manifestRaw through exit 2
# Insert EXE-first attempt before manifest; on success jump to ship+exit2

apply_marker = "$manifestRaw = Invoke-SshCat -Target $ep.Target -RemotePath \"$RemoteBundle/manifest.txt\""
if 'Invoke-ExeOnlyClientUpdate -Target' in text and 'exe_only_primary' in text:
    print('apply section already has exe_only_primary')
else:
    if apply_marker not in text:
        raise SystemExit('apply marker not found')
    insert = '''# --- EXE-only primary update (bat or EXE launch) ---
Write-UpdateFileLog 'exe_only_primary try=1'
if (Invoke-ExeOnlyClientUpdate -Target $ep.Target -RemoteVer $remoteVer) {
    Write-UpdateMsg "Updated to v$remoteVer" 'Green'
    Write-UpdateFileLog 'applied_ok via=exe_only need_relaunch exit=2'
    try {
        $dayLog = Get-UpdateLogPath
        $cfg = Join-Path $env:USERPROFILE '.config\\claude-connect\\connect.conf'
        $ru=''; $sip=''
        if (Test-Path $cfg) {
            Get-Content $cfg | ForEach-Object {
                if ($_ -match '^REMOTE_USER=(.+)$') { $ru=$Matches[1].Trim() }
            }
        }
        if (Get-Command Get-LocalServerIp -ErrorAction SilentlyContinue) { $sip = Get-LocalServerIp }
        if ($ru -and $sip -and (Test-Path $dayLog)) {
            $t = "{0}@{1}" -f $ru,$sip
            $wmPath = $dayLog + '.sync-offset'
            $off = 0
            if (Test-Path -LiteralPath $wmPath) {
                $raw = ((Get-Content -LiteralPath $wmPath -Raw -ErrorAction SilentlyContinue) + '').Trim()
                [void][int]::TryParse($raw, [ref]$off)
                if ($off -lt 0) { $off = 0 }
            }
            $fileLen = [int64]0
            $take = 0
            $chunk = $null
            $fsRead = $null
            try {
                $fsRead = [System.IO.File]::Open(
                    $dayLog,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite)
                $fileLen = [int64]$fsRead.Length
                if ($off -gt $fileLen) { $off = 0 }
                if ($off -lt $fileLen) {
                    $take = [int][Math]::Min(512KB, $fileLen - $off)
                    $null = $fsRead.Seek([int64]$off, [System.IO.SeekOrigin]::Begin)
                    $chunk = New-Object byte[] $take
                    $got = $fsRead.Read($chunk, 0, $take)
                    if ($got -lt $take) {
                        $take = $got
                        $trimmed = New-Object byte[] $take
                        [Array]::Copy($chunk, 0, $trimmed, 0, $take)
                        $chunk = $trimmed
                    }
                }
            } finally {
                if ($fsRead) { try { $fsRead.Dispose() } catch { } }
            }
            if ($take -gt 0 -and $null -ne $chunk) {
                $tmpLocal = Join-Path $env:TEMP ("claude-upd-chunk-{0}.log" -f $PID)
                [System.IO.File]::WriteAllBytes($tmpLocal, $chunk)
                $day = Get-Date -Format 'yyyyMMdd'
                $remoteTmp = ".claude/logs/.connect-upd-$PID.tmp"
                $remoteDay = ".claude/logs/connect-$day.log"
                $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; true'
                $sshOpts = $script:SshCommonOpts + @($t, $mk)
                $rMk = Invoke-SshTimed -ArgumentList $sshOpts -TimeoutMs 12000
                if ($rMk.Ok) {
                    $scpArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','-q', $tmpLocal, "${t}:$remoteTmp")
                    $rScp = Invoke-SshTimed -Exe 'scp' -ArgumentList $scpArgs -TimeoutMs 20000
                    if ($rScp.Ok) {
                        $cat = 'cat "$HOME/' + $remoteTmp + '" >> "$HOME/' + $remoteDay + '"; ec=$?; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '" 2>/dev/null; exit $ec'
                        $rCat = Invoke-SshTimed -ArgumentList ($script:SshCommonOpts + @($t, $cat)) -TimeoutMs 12000
                        if ($rCat.Ok) {
                            $newOff = $off + $take
                            Set-Content -LiteralPath $wmPath -Value "$newOff" -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
                            Write-UpdateFileLog ("shipped_day_log_to_server target=$t bytes=$take offset=$newOff")
                        } else {
                            Write-UpdateFileLog 'SHIP_FAIL cat' 'WARN'
                        }
                    } else {
                        Write-UpdateFileLog 'SHIP_FAIL scp' 'WARN'
                    }
                } else {
                    Write-UpdateFileLog 'SHIP_FAIL mkdir' 'WARN'
                }
                Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue
            } else {
                Write-UpdateFileLog 'ship_skip already_synced'
            }
        } else {
            Write-UpdateFileLog 'ship_skip no_conf_or_log'
        }
    } catch {
        Write-UpdateFileLog ("SHIP_FAIL ex=" + $_.Exception.Message) 'WARN'
    }
    Sync-ConnectExeBesideClient
    Release-ConnectSingleInstanceForUpdateRelaunch
    exit 2
}

Write-UpdateFileLog 'exe_only_fallback_to_bundle' 'WARN'
Write-UpdateMsg '  EXE update unavailable - falling back to full bundle...' 'DarkYellow'

''' + apply_marker
    text = text.replace(apply_marker, insert, 1)
    print('inserted exe-only primary before manifest apply')

upd.write_text(text, encoding='utf-8', newline='\n')
print('wrote', upd)

# Patch build-windows-exe.ps1 setup-launch for NO_LAUNCH
b = build.read_text(encoding='utf-8')
old_alive = '''    $alive = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ([string]$_.CommandLine -match 'Claude-Connect\\\\connect-boot\\.ps1')
    })
    if ($alive.Count -gt 0) {
        Log ("already_running count={0} - not opening another window" -f $alive.Count)
        Write-Host ''
        Write-Host '  Claude Connect is already running.' -ForegroundColor Yellow
        Write-Host '  Close the existing window, then run the EXE again if needed.' -ForegroundColor Yellow
        Write-Host ''
        Start-Sleep -Seconds 5
        exit 0
    }

    Log 'launching connect.bat (hidden console -> one PowerShell UI)'
    # Hidden cmd runs connect.bat; bat starts visible powershell and exits.
    Start-Process -FilePath 'cmd.exe' -WorkingDirectory $Dest -ArgumentList @('/c', 'connect.bat') -WindowStyle Minimized
    Log 'setup ok'
    exit 0'''

new_alive = '''    if ($env:CLAUDE_CONNECT_SETUP_NO_LAUNCH -eq '1') {
        Log 'setup files-only (NO_LAUNCH=1) - skip connect.bat'
        exit 0
    }

    $alive = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ([string]$_.CommandLine -match 'Claude-Connect\\\\connect-boot\\.ps1')
    })
    if ($alive.Count -gt 0) {
        Log ("already_running count={0} - not opening another window" -f $alive.Count)
        Write-Host ''
        Write-Host '  Claude Connect is already running.' -ForegroundColor Yellow
        Write-Host '  Close the existing window, then run the EXE again if needed.' -ForegroundColor Yellow
        Write-Host ''
        Start-Sleep -Seconds 5
        exit 0
    }

    Log 'launching connect.bat (hidden console -> one PowerShell UI)'
    # Hidden cmd runs connect.bat; bat starts visible powershell and exits.
    Start-Process -FilePath 'cmd.exe' -WorkingDirectory $Dest -ArgumentList @('/c', 'connect.bat') -WindowStyle Minimized
    Log 'setup ok'
    exit 0'''

# In the here-string the escapes are single backslash for regex in the file
# Read actual content around already_running
if "CLAUDE_CONNECT_SETUP_NO_LAUNCH" in b:
    print('build-windows-exe already has NO_LAUNCH')
else:
    needle = "    $alive = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {\n        ([string]$_.CommandLine -match 'Claude-Connect\\\\connect-boot\\.ps1')\n    })"
    # File content uses single-escaped in the @' '@ string: Claude-Connect\\connect-boot\.ps1
    # In the actual .ps1 file as stored, inside @' '@ it's: Claude-Connect\\connect-boot\.ps1
    idx = b.find("$alive = @(Get-CimInstance Win32_Process")
    if idx < 0:
        raise SystemExit('alive block not found in build-windows-exe')
    # Insert NO_LAUNCH check just before $alive
    insert_nl = """    if ($env:CLAUDE_CONNECT_SETUP_NO_LAUNCH -eq '1') {
        Log 'setup files-only (NO_LAUNCH=1) - skip connect.bat'
        exit 0
    }

"""
    b = b[:idx] + insert_nl + b[idx:]
    build.write_text(b, encoding='utf-8', newline='\n')
    print('patched build-windows-exe NO_LAUNCH')

print('OK')
