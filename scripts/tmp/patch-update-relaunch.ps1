# patch-update-relaunch.ps1 - fix stale bat frame after self-update
Set-StrictMode -Version Latest
Set-Location (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$utf8 = New-Object System.Text.UTF8Encoding $false

# --- connect-update.ps1 ---
$updPath = Join-Path $PWD 'scripts/client/windows/connect-update.ps1'
$upd = [IO.File]::ReadAllText($updPath)
if ($upd -notmatch 'function Invoke-ConnectPs1Relaunch') {
  $fn = @'

function Invoke-ConnectPs1Relaunch {
    param([string]$ScriptDir)
    try {
        $bat = Join-Path $ScriptDir 'connect.bat'
        if (-not (Test-Path -LiteralPath $bat)) {
            Write-UpdateFileLog 'relaunch_skip no_connect_bat' 'WARN'
            return
        }
        $depth = 0
        if ($env:CLAUDE_CONNECT_UPDATE_DEPTH) {
            [void][int]::TryParse(($env:CLAUDE_CONNECT_UPDATE_DEPTH + '').Trim(), [ref]$depth)
        }
        if ($depth -lt 0) { $depth = 0 }
        $depth++
        $relaunchRunId = [guid]::NewGuid().ToString('N').Substring(0, 12)
        $marker = Join-Path $ScriptDir '.client-update-relaunch'
        Set-Content -LiteralPath $marker -Value $relaunchRunId -Encoding ASCII -NoNewline -ErrorAction Stop
        $cmdLine = ('set "CLAUDE_CONNECT_UPDATE_DEPTH={0}"&& set "CLAUDE_CONNECT_RUN_ID={1}"&& set "CLAUDE_CONNECT_IS_RELAUNCH=1"&& start "" /D "{2}" "{3}"' -f $depth, $relaunchRunId, $ScriptDir, $bat)
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmdLine -WorkingDirectory $ScriptDir -WindowStyle Normal | Out-Null
        Write-UpdateFileLog ("relaunch_spawned depth=$depth run_id=$relaunchRunId")
    } catch {
        Write-UpdateFileLog ("relaunch_fail err=$($_.Exception.Message)") 'ERROR'
    }
}

'@
  $upd = $upd.Replace('function Get-UpdateLogPath {', ($fn + 'function Get-UpdateLogPath {'))
  $oldExit = "    exit 2`r`n`r`n"
  $newExit = "    Invoke-ConnectPs1Relaunch -ScriptDir `$ScriptDir`r`n    exit 2`r`n`r`n"
  if ($upd.Contains($oldExit)) {
    $upd = $upd.Replace($oldExit, $newExit)
  } elseif ($upd.Contains("    exit 2`n`n")) {
    $upd = $upd.Replace("    exit 2`n`n", ($newExit -replace "`r", ''))
  } else {
    throw 'connect-update.ps1 exit 2 anchor not found'
  }
  [IO.File]::WriteAllText($updPath, $upd, $utf8)
  Write-Host 'OK connect-update.ps1' -ForegroundColor Green
} else {
  Write-Host 'SKIP connect-update.ps1' -ForegroundColor Yellow
}

# --- connect.ps1 ---
$cpPath = Join-Path $PWD 'scripts/client/windows/connect.ps1'
$cp = [IO.File]::ReadAllText($cpPath)
if ($cp -notmatch 'Test-ConnectStaleUpdateFrame') {
  $guard = @'

function Test-ConnectStaleUpdateFrame {
    param([string]$ScriptDir)
    $marker = Join-Path $ScriptDir '.client-update-relaunch'
    if (-not (Test-Path -LiteralPath $marker)) { return $false }
    try {
        $want = ((Get-Content -LiteralPath $marker -Raw -ErrorAction Stop) + '').Trim()
    } catch { return $false }
    if (-not $want) { return $false }
    $mine = ($env:CLAUDE_CONNECT_RUN_ID + '').Trim()
    if (($env:CLAUDE_CONNECT_IS_RELAUNCH -eq '1') -and $mine -eq $want) {
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        return $false
    }
    return $true
}

if (Test-ConnectStaleUpdateFrame -ScriptDir $script:ConnectScriptDir) { exit 0 }

'@
  $anchor = '$script:ConnectScriptDir = if ($PSScriptRoot)'
  $idx = $cp.IndexOf($anchor)
  if ($idx -lt 0) { throw 'connect.ps1 anchor missing' }
  $lineEnd = $cp.IndexOf("`n", $idx)
  $cp = $cp.Insert($lineEnd + 1, $guard)
  [IO.File]::WriteAllText($cpPath, $cp, $utf8)
  Write-Host 'OK connect.ps1' -ForegroundColor Green
} else {
  Write-Host 'SKIP connect.ps1' -ForegroundColor Yellow
}

# --- connect.bat ---
$batPath = Join-Path $PWD 'scripts/client/windows/connect.bat'
$bat = [IO.File]::ReadAllText($batPath)
$oldBat = @'
            REM Spawn a fresh process then CLOSE this console (call/exit /b left the
            REM update window open on top of Connect — felt like "opens but won't close").
            start "" /D "%HERE%" "%~f0" %*
            exit 0
'@
$newBat = @'
            REM connect-update.ps1 spawns relaunch + marker; close stale console.
            if exist "%HERE%.client-update-relaunch" (
                exit 0
            )
            REM Fallback if PS1 relaunch failed (no marker).
            start "" /D "%HERE%" "%~f0" %*
            exit 0
'@
$batN = ($bat -replace "`r`n", "`n")
$oldBatN = ($oldBat -replace "`r`n", "`n")
$newBatN = ($newBat -replace "`r`n", "`n")
if ($batN.Contains($oldBatN)) {
  $batN = $batN.Replace($oldBatN, $newBatN)
  [IO.File]::WriteAllText($batPath, ($batN -replace "`n", "`r`n"), $utf8)
  Write-Host 'OK connect.bat' -ForegroundColor Green
} elseif ($batN -match '\.client-update-relaunch') {
  Write-Host 'SKIP connect.bat' -ForegroundColor Yellow
} else {
  throw 'connect.bat relaunch block not found'
}

# --- bump version ---
. (Join-Path $PWD 'publish/bump-connect-version.ps1')
$v = Invoke-BumpConnectVersion -ProjectRoot $PWD
Write-Host "BUMPED $v" -ForegroundColor Cyan
