#Requires -Version 5.1
# LIVE GREEN (Plan Task 4 / P0-L1): Mount BG day-log under parent FileStream mutex contention.
# Write-MountBgLog uses Global\ClaudeConnectDayLogWrite-<dayTag> (same as Get-ConnectLogWriteMutex),
# Seek End before write, and .mount-bg sidecar fallback so MOUNT_BG_* survives parent FileStream hold.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Mount BG day-log mutex contention (LIVE GREEN / Task 4) ===' -ForegroundColor Cyan

$connectPath = Get-ClientFile 'windows\connect.ps1'
$connectUiPath = Get-ClientFile 'connect-ui.ps1'
$connect = Get-Content -LiteralPath $connectPath -Raw
$connectUi = Get-Content -LiteralPath $connectUiPath -Raw

$bgFn = Get-FunctionSource -Content $connect -Name 'Start-MountProjectBackground'
Assert ($null -ne $bgFn -and $bgFn.Length -gt 200) 'extracted Start-MountProjectBackground from connect.ps1'

# Write-MountBgLog exists only inside the runner here-string; extract from that body.
$writerFn = Get-FunctionSource -Content $connect -Name 'Write-MountBgLog'
if (-not $writerFn) { $writerFn = Get-FunctionSource -Content $bgFn -Name 'Write-MountBgLog' }
Assert ($null -ne $writerFn -and $writerFn.Length -gt 80) 'extracted Write-MountBgLog from mount-bg runner'

$mutexFn = Get-FunctionSource -Content $connectUi -Name 'Get-ConnectLogWriteMutex'
Assert ($null -ne $mutexFn) 'extracted Get-ConnectLogWriteMutex from connect-ui.ps1 (name algorithm source of truth)'
Assert ($mutexFn -match 'Global\\ClaudeConnectDayLogWrite-') 'Get-ConnectLogWriteMutex uses Global\ClaudeConnectDayLogWrite-<dayTag>'

# --- Source GREEN contract ---
Assert ($writerFn -notmatch '\[System\.IO\.File\]::AppendAllText') `
    'GREEN: Write-MountBgLog no longer uses File.AppendAllText'
Assert ($writerFn -match 'Global\\ClaudeConnectDayLogWrite-') `
    'GREEN: Write-MountBgLog uses exact mutex Global\ClaudeConnectDayLogWrite-<dayTag>'
Assert ($writerFn -notmatch 'Global\\ClaudeConnectLogWrite[^-]') `
    'GREEN: Write-MountBgLog must not invent Global\ClaudeConnectLogWrite (wrong name)'
# Product uses [System.IO.SeekOrigin]::End (]::End), not SeekOrigin.End literal.
$hasSeekEof = [bool]($writerFn -match 'Seek\s*\(\s*0\s*,' -and $writerFn -match 'SeekOrigin')
$hasSidecar = [bool]($writerFn -match '\.mount-bg')
Assert $hasSeekEof 'GREEN: Write-MountBgLog Seek(0, ...) + SeekOrigin before write'
Assert $hasSidecar 'GREEN: Write-MountBgLog .mount-bg sidecar fallback'

# --- LIVE: parent holds day-log FileStream (same share mode as Initialize-ConnectLog) ---
$tmpLogDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-mountbg-mutex-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmpLogDir | Out-Null
$dayTag = Get-Date -Format 'yyyyMMdd'
$day = Join-Path $tmpLogDir ("connect-{0}.log" -f $dayTag)
$sessionId = 'mountbgmutex01'
$marker = "MOUNT_BG_BEGIN project=mutex-contention-test"

$parentFs = $null
$childScript = Join-Path $tmpLogDir 'child-write-mountbg.ps1'
try {
    # Seed file so Append open succeeds for parent.
    [System.IO.File]::WriteAllText($day, "", [System.Text.UTF8Encoding]::new($false))
    $parentFs = [System.IO.FileStream]::new(
        $day,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite)

        # Child process uses the EXACT Write-MountBgLog body from product (AppendAllText today).
    # Concatenate with single-quoted fragments so $LogDir/$SessionId inside $writerFn stay literal.
    $childBody = @(
        "param([string]`$LogDir, [string]`$SessionId, [string]`$Msg)"
        "`$ErrorActionPreference = 'Continue'"
        $writerFn
        "Write-MountBgLog `$Msg 'INFO'"
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $childScript -Value $childBody -Encoding UTF8

    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $childScript,
        '-LogDir', $tmpLogDir, '-SessionId', $sessionId, '-Msg', $marker
    ) -WindowStyle Hidden -PassThru -Wait
    Write-Host ("  INFO  child exit={0} (mutex+Seek EOF under parent FileStream)" -f $p.ExitCode) -ForegroundColor DarkGray

    $logText = ''
    if (Test-Path -LiteralPath $day) {
        # Read via a separate share-friendly open while parent still holds the stream.
        $readFs = $null
        try {
            $readFs = [System.IO.FileStream]::new(
                $day, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $sr = New-Object System.IO.StreamReader($readFs, [System.Text.UTF8Encoding]::new($false), $false)
            $logText = $sr.ReadToEnd()
            $sr.Dispose()
        } finally {
            if ($readFs) { try { $readFs.Dispose() } catch { } }
        }
    }

    $childAppeared = [bool]($logText -match [regex]::Escape($marker) -or $logText -match "\[$sessionId\]\s*$([regex]::Escape('MOUNT_BG_BEGIN'))")
    $sidecarPath = $day + '.mount-bg'
    $sidecarAppeared = (Test-Path -LiteralPath $sidecarPath) -and (
        (Get-Content -LiteralPath $sidecarPath -Raw -ErrorAction SilentlyContinue) -match 'MOUNT_BG_BEGIN'
    )

    if (-not $childAppeared -and -not $sidecarAppeared) {
        Write-Host '  INFO  RED evidence: child line absent under parent FileStream (AppendAllText silent / swallowed)' -ForegroundColor DarkGray
    }

    # GREEN live contract: child line (or sidecar) must appear while parent still holds the stream.
    Assert ($childAppeared -or $sidecarAppeared) `
        'GREEN contract: under parent FileStream Append+ReadWrite, Mount BG child line must appear in day log (or .mount-bg) within process lifetime — not swallowed by empty catch'
} finally {
    if ($parentFs) { try { $parentFs.Dispose() } catch { } }
    Remove-Item -LiteralPath $tmpLogDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'ALL PASS (GREEN): Mount BG day-log survives parent FileStream via mutex/seek/sidecar.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail FAIL (Task 4 GREEN: mutex/seek-EOF/.mount-bg + visible MOUNT_BG_* under contention)" -ForegroundColor Red
exit 1

