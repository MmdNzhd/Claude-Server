@echo off
REM connect.bat - double-click launcher for Windows.
setlocal EnableDelayedExpansion
REM Hide the launcher console: re-run minimized, then only the PowerShell UI stays visible.
if not defined CLAUDE_CONNECT_BAT_INNER (
    set "CLAUDE_CONNECT_BAT_INNER=1"
    start "" /MIN cmd /d /c ""%~f0" %*"
    exit /b 0
)
set "HERE=%~dp0"
set "HERE_NOTRAIL=%HERE:~0,-1%"
set "HERE_IS_SEPIDZ=0"
echo.%HERE%| find /I "claude-code-sepidz" >nul && set "HERE_IS_SEPIDZ=1"
echo.%HERE%| find /I "Claude-Connect-Sepidz" >nul && set "HERE_IS_SEPIDZ=1"
title Claude Connect

REM Stage 6: when connect-preflight.ps1 exists, happy path uses one PS preflight then connect-boot
REM (skips scattered bootstrap/heal/update PS starts). Sepidz / OUTDATED / error paths unchanged.
if exist "%HERE%connect-preflight.ps1" (
    if not defined CLAUDE_CONNECT_UPDATE_DEPTH set "CLAUDE_CONNECT_UPDATE_DEPTH=0"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-preflight.ps1" -Here "%HERE_NOTRAIL%"
    set "PRE_EC=!errorlevel!"
    if exist "%TEMP%\claude-connect-run-id.txt" (
        for /f "usebackq delims=" %%I in ("%TEMP%\claude-connect-run-id.txt") do set "CLAUDE_CONNECT_RUN_ID=%%I"
    )
    if "!PRE_EC!"=="2" (
        echo.%HERE%| find /I "claude-code-sepidz" >nul && goto AFTER_CLIENT_UPDATE
        echo.%HERE%| find /I "Claude-Connect-Sepidz" >nul && goto AFTER_CLIENT_UPDATE
        goto HEAL_RELAUNCH
    )
    if "!PRE_EC!"=="3" (
        set /a CLAUDE_CONNECT_UPDATE_DEPTH+=1
        if !CLAUDE_CONNECT_UPDATE_DEPTH! GEQ 3 (
            echo.
            echo   [X] Update relaunch limit reached - continuing with current files.
            echo.
            goto AFTER_CLIENT_UPDATE
        )
        echo.
        echo   Restarting with updated files...
        echo.
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $bat='%~f0'; $dir='%HERE_NOTRAIL%'; Start-Sleep -Seconds 2; $p=Start-Process -FilePath $bat -WorkingDirectory $dir -PassThru -WindowStyle Hidden; if (-not $p) { throw 'Start-Process returned null' }; exit 0 } catch { exit 1 }"
        if errorlevel 1 (
            ping -n 2 127.0.0.1 >nul
            start /MIN "Claude Connect" /D "%HERE_NOTRAIL%" cmd /c ""%~f0" %*"
        )
        exit
    )
    goto AFTER_CLIENT_UPDATE
)

REM Stable run id: correlates BOOTSTRAP / UPDATE / session start in the day log
REM setlocal env vars inherit to child powershell -File (connect-update.ps1, connect.ps1).

if not defined CLAUDE_CONNECT_RUN_ID (

  for /f %%I in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N').Substring(0,12)"') do set "CLAUDE_CONNECT_RUN_ID=%%I"

)

REM Log double-click immediately (before update) - durable local day log (BOM-less)

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [INFO] [{1}] BOOTSTRAP: connect.bat start here={2}' -f $ts, $sid, '%HERE%'); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul


if not defined CLAUDE_CONNECT_UPDATE_DEPTH set "CLAUDE_CONNECT_UPDATE_DEPTH=0"

REM 1) Server bootstrap pull (works even if local connect-update is broken)
REM    If connect-bootstrap.ps1 is missing (ancient folders), try Claude-Connect copy first, else skip.
set "BOOT_EC=0"
if exist "%HERE%connect-bootstrap.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-bootstrap.ps1" -Here "%HERE_NOTRAIL%" -Quiet
    set "BOOT_EC=!errorlevel!"
) else if "!HERE_IS_SEPIDZ!"=="1" (
    REM Never pull/copy Smart Claude-Connect bootstrap into a Sepidz tree.
    set "BOOT_EC=0"
) else if exist "%USERPROFILE%\Desktop\Claude-Connect\connect-bootstrap.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Desktop\Claude-Connect\connect-bootstrap.ps1" -Here "%HERE_NOTRAIL%" -Quiet
    set "BOOT_EC=!errorlevel!"
) else (
    REM Ancient bat/folder: detect broken update and force-copy bootstrap from stable publish if present
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $here='%HERE_NOTRAIL%'; $upd=Join-Path $here 'connect-update.ps1'; $broken=$false; if(Test-Path $upd){ $r=Get-Content -LiteralPath $upd -Raw -EA SilentlyContinue; if($r -match 'UpdateEndpointTarget'){ $broken=$true } }; $stable=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client\windows'; $canon=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'; $src=$null; foreach($c in @($canon,$stable)){ if(Test-Path (Join-Path $c 'connect-bootstrap.ps1')){ $src=$c; break } }; if($broken -and $src){ foreach($n in @('connect-bootstrap.ps1','connect-heal.ps1','connect-update.ps1','connect.bat','cursor-proxy-sidecar.ps1','connect-version.txt')){ $s=Join-Path $src $n; if(Test-Path $s){ Copy-Item -Force $s (Join-Path $here $n) } }; if(Test-Path (Join-Path $here 'connect-bootstrap.ps1')){ $p=Start-Process -FilePath powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $here 'connect-bootstrap.ps1'),'-Here',$here,'-Quiet','-Force') -Wait -PassThru -WindowStyle Hidden; if($p -and $p.ExitCode -eq 2){ exit 2 } } }; exit 0 } catch { exit 0 }"
    set "BOOT_EC=!errorlevel!"
)
if "!BOOT_EC!"=="2" (
    echo.%HERE%| find /I "claude-code-sepidz" >nul && goto AFTER_HEAL_RELAUNCH
    echo.%HERE%| find /I "Claude-Connect-Sepidz" >nul && goto AFTER_HEAL_RELAUNCH
    goto HEAL_RELAUNCH
)

REM 2) Local heal / redirect away from dated publish folders
set "HEAL_EC=0"
if exist "%HERE%connect-heal.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-heal.ps1" -Here "%HERE_NOTRAIL%"
    set "HEAL_EC=!errorlevel!"
) else if "!HERE_IS_SEPIDZ!"=="1" (
    REM Never inline-copy Smart Claude-Connect into a Sepidz tree.
    set "HEAL_EC=0"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $here='%HERE_NOTRAIL%'; $canon=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'; $stable=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client\windows'; $legacy=($here -match 'claude-code-client-\d{8}' -or $here -match 'claude-code-sepidz-\d{8}' -or $here -match '[\\/]claude-publish[\\/]'); function Good($d){ if(-not (Test-Path (Join-Path $d 'connect.bat'))){return $false}; if(-not (Test-Path (Join-Path $d 'cursor-proxy-sidecar.ps1'))){return $false}; $u=Join-Path $d 'connect-update.ps1'; if(-not (Test-Path $u)){return $false}; $r=Get-Content -LiteralPath $u -Raw -EA SilentlyContinue; if($r -match 'UpdateEndpointTarget'){return $false}; return $true }; $src=$null; foreach($c in @($canon,$stable)){ if(Good $c){ $src=$c; break } }; if(-not $src){ exit 0 }; $names=@('connect.bat','connect-boot.ps1','connect-bootstrap.ps1','connect-heal.ps1','connect.ps1','connect-update.ps1','cursor-proxy-sidecar.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1','windows-mcp-laptop.ps1','connect-version.txt'); if(-not (Good $canon)){ New-Item -ItemType Directory -Force -Path $canon|Out-Null; foreach($n in $names){ $s=Join-Path $src $n; if(Test-Path $s){ Copy-Item -Force $s (Join-Path $canon $n) } } }; $need=(-not (Good $here)); if($need){ foreach($n in $names){ $s=Join-Path $canon $n; if(Test-Path $s){ Copy-Item -Force $s (Join-Path $here $n) } } }; if($legacy -and (Good $canon) -and ($here -ne $canon)){ Set-Content -LiteralPath (Join-Path $env:TEMP 'claude-connect-relaunch.dir') -Value $canon -Encoding ASCII; exit 2 }; exit 0 } catch { exit 1 }"
    set "HEAL_EC=!errorlevel!"
)
if "!HEAL_EC!"=="2" (
    echo.%HERE%| find /I "claude-code-sepidz" >nul && goto AFTER_HEAL_RELAUNCH
    echo.%HERE%| find /I "Claude-Connect-Sepidz" >nul && goto AFTER_HEAL_RELAUNCH
    goto HEAL_RELAUNCH
)
goto AFTER_HEAL_RELAUNCH

:HEAL_RELAUNCH
set "RELAUNCH_DIR=%USERPROFILE%\Desktop\Claude-Connect"
if exist "%TEMP%\claude-connect-relaunch.dir" (
    for /f "usebackq delims=" %%D in ("%TEMP%\claude-connect-relaunch.dir") do set "RELAUNCH_DIR=%%D"
)
echo.
echo   Switching to canonical folder:
echo   !RELAUNCH_DIR!\connect.bat
echo.
set "CLAUDE_CONNECT_SKIP_HEAL=1"
set "CLAUDE_CONNECT_SKIP_BOOTSTRAP=1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $dir='!RELAUNCH_DIR!'; if (-not $dir) { $dir=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect' }; $bat=Join-Path $dir 'connect.bat'; if (-not (Test-Path -LiteralPath $bat)) { throw 'missing bat' }; $p=Start-Process -FilePath $bat -WorkingDirectory $dir -PassThru -WindowStyle Hidden; if (-not $p) { throw 'Start-Process null' }; exit 0 } catch { exit 1 }"
if errorlevel 1 (
    start /MIN "Claude Connect" /D "%USERPROFILE%\Desktop\Claude-Connect" cmd /c ""%USERPROFILE%\Desktop\Claude-Connect\connect.bat" %*"
)
exit

:AFTER_HEAL_RELAUNCH

REM Sepidz frozen bat package: never block on server auto-update SSH.
set "SKIP_CLIENT_UPDATE=0"
echo.%HERE%| find /I "claude-code-sepidz" >nul && set "SKIP_CLIENT_UPDATE=1"
echo.%HERE%| find /I "Claude-Connect-Sepidz" >nul && set "SKIP_CLIENT_UPDATE=1"
if "!SKIP_CLIENT_UPDATE!"=="1" (
    echo.
    echo   Sepidz package: skipping client auto-update.
    echo.
    goto AFTER_CLIENT_UPDATE
)

if exist "%HERE%connect-update.ps1" (
    REM Visible progress modal during Quiet update (STA required for WinForms).
    set "CLAUDE_CONNECT_UPDATE_UI=1"
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect-update.ps1" -ScriptDir "%HERE_NOTRAIL%" -Quiet
    set "UPD_EC=!errorlevel!"
    if !UPD_EC! EQU 1 (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL UPDATE_BAT_EXIT: connect-update.ps1 exit=1 (update failed)' -f $ts, $sid); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
        REM Update failed - force server pull into Claude-Connect, then relaunch canon (depth-limited)
        set /a CLAUDE_CONNECT_UPDATE_DEPTH+=1
        if !CLAUDE_CONNECT_UPDATE_DEPTH! GEQ 3 (
            echo.
            echo   [X] Update failed repeatedly - continuing with current files.
            echo       If this keeps happening, run Desktop\Claude-Connect\connect.bat once more
            echo       or reinstall from the latest Claude-Connect.exe.
            echo.
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL UPDATE_FAIL_RELAUNCH_LIMIT: depth^>=3 after exit=1 continuing' -f $ts, $sid); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
        ) else (
            echo.
            echo   [!] Update failed - pulling latest from server into Desktop\Claude-Connect ...
            echo.
            if exist "%HERE%connect-bootstrap.ps1" (
                powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-bootstrap.ps1" -Here "%HERE_NOTRAIL%" -Quiet -Force
            ) else (
                if exist "%USERPROFILE%\Desktop\Claude-Connect\connect-bootstrap.ps1" (
                    powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Desktop\Claude-Connect\connect-bootstrap.ps1" -Here "%HERE_NOTRAIL%" -Quiet -Force
                )
            )
            set "SKIP_SMART_RELAUNCH=0"
            echo.%HERE%| find /I "claude-code-sepidz" >nul && set "SKIP_SMART_RELAUNCH=1"
            echo.%HERE%| find /I "Claude-Connect-Sepidz" >nul && set "SKIP_SMART_RELAUNCH=1"
            if "!SKIP_SMART_RELAUNCH!"=="0" if exist "%USERPROFILE%\Desktop\Claude-Connect\connect.bat" (
                set "CLAUDE_CONNECT_SKIP_HEAL=1"
                set "CLAUDE_CONNECT_SKIP_BOOTSTRAP=1"
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $dir=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'; $bat=Join-Path $dir 'connect.bat'; Start-Process -FilePath $bat -WorkingDirectory $dir -WindowStyle Hidden; exit 0 } catch { exit 1 }"
                if not errorlevel 1 exit
            )
        )
    )
    if !UPD_EC! EQU 2 (
        set /a CLAUDE_CONNECT_UPDATE_DEPTH+=1
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [INFO] [{1}] BAT_RELAUNCH: begin depth={2} dir={3} upd_ec=2' -f $ts, $sid, $env:CLAUDE_CONNECT_UPDATE_DEPTH, '%HERE_NOTRAIL%'); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
        if !CLAUDE_CONNECT_UPDATE_DEPTH! GEQ 3 (
            echo.
            echo   [X] Update relaunch limit reached - continuing with current files.
            echo.
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL BAT_RELAUNCH: limit depth={2} (>=3) continuing with current files' -f $ts, $sid, $env:CLAUDE_CONNECT_UPDATE_DEPTH); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)); $line2=('[{0}] [ERROR] [{1}] FAIL UPDATE_RELAUNCH_LIMIT: depth>=3 continuing with current files' -f $ts, $sid); [IO.File]::AppendAllText($f, $line2+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
        ) else (
            echo.
            echo   Restarting with updated files...
            echo.
            REM Self-heal: Start-Process the updated bat (cmd `start` can silently fail).
            REM HERE_NOTRAIL: trailing backslash breaks /D quoting (Aria: exit=2, no BOOTSTRAP).
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $bat='%~f0'; $dir='%HERE_NOTRAIL%'; $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $line=('[{0}] [INFO] [{1}] BAT_RELAUNCH: attempt depth={2} dir={3} bat={4}' -f $ts, $sid, $env:CLAUDE_CONNECT_UPDATE_DEPTH, $dir, $bat); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)); Start-Sleep -Seconds 2; $p=Start-Process -FilePath $bat -WorkingDirectory $dir -PassThru -WindowStyle Hidden; if (-not $p) { throw 'Start-Process returned null' }; $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $line=('[{0}] [INFO] [{1}] BAT_RELAUNCH: ok depth={2} dir={3} pid={4} via=Start-Process' -f $ts, $sid, $env:CLAUDE_CONNECT_UPDATE_DEPTH, $dir, $p.Id); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)); $line2=('[{0}] [INFO] [{1}] UPDATE: bat_relaunch depth={2} dir={3} pid={4} via=Start-Process' -f $ts, $sid, $env:CLAUDE_CONNECT_UPDATE_DEPTH, $dir, $p.Id); [IO.File]::AppendAllText($f, $line2+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)); exit 0 } catch { try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL BAT_RELAUNCH: {2}' -f $ts, $sid, ($_.Exception.Message -replace '[\r\n]',' ')); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}; exit 1 }"
            if errorlevel 1 (
                REM Fallback if Start-Process failed
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [WARN] [{1}] BAT_RELAUNCH: fallback_start_cmd depth={2} dir={3}' -f $ts, $sid, $env:CLAUDE_CONNECT_UPDATE_DEPTH, '%HERE_NOTRAIL%'); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
                ping -n 2 127.0.0.1 >nul
                start /MIN "Claude Connect" /D "%HERE_NOTRAIL%" cmd /c ""%~f0" %*"
                if errorlevel 1 (
                    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL BAT_RELAUNCH: fallback_start_cmd failed depth={2}' -f $ts, $sid, $env:CLAUDE_CONNECT_UPDATE_DEPTH); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
                )
            )
            REM Close THIS console (double-click / leftover /K windows should die here).
            exit
        )
    )
)

:AFTER_CLIENT_UPDATE

set "OUTDATED=0"
if not exist "%HERE%connect.ps1" set "OUTDATED=1"
if not exist "%HERE%connect-boot.ps1" set "OUTDATED=1"
if not exist "%HERE%connect-ui.ps1" set "OUTDATED=1"
if not exist "%HERE%editor-launch.ps1" set "OUTDATED=1"
if not exist "%HERE%windows-mcp-laptop.ps1" set "OUTDATED=1"
if not exist "%HERE%git-mode.ps1" set "OUTDATED=1"
if not exist "%HERE%cursor-auth-laptop.ps1" set "OUTDATED=1"
if not exist "%HERE%connect-diagnostic.ps1" set "OUTDATED=1"
if not exist "%HERE%cursor-proxy-sidecar.ps1" set "OUTDATED=1"
if not exist "%HERE%connect-version.txt" set "OUTDATED=1"
findstr /C:"Path.Combine" "%HERE%editor-launch.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"@(Choose-Project" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"g git" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"Acquire-TunnelPort" "%HERE%git-mode.ps1" >nul 2>&1 || set "OUTDATED=1"
set "EXPECT_VER="
if exist "%HERE%connect-version.txt" (
    for /f "usebackq delims=" %%V in ("%HERE%connect-version.txt") do set "EXPECT_VER=%%V"
)
if not defined EXPECT_VER set "OUTDATED=1"
if defined EXPECT_VER findstr /C:"ConnectVersion = '!EXPECT_VER!'" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"

if "%OUTDATED%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $here='%HERE%'; $line=('[{0}] [ERROR] [{1}] FAIL OUTDATED_SCRIPTS: folder incomplete or mismatched version here={2}' -f $ts, $sid, $here); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
    if exist "%HERE%connect-bootstrap.ps1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-bootstrap.ps1" -Here "%HERE_NOTRAIL%" -Quiet -Force
    ) else if not "!HERE_IS_SEPIDZ!"=="1" if exist "%USERPROFILE%\Desktop\Claude-Connect\connect-bootstrap.ps1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Desktop\Claude-Connect\connect-bootstrap.ps1" -Here "%HERE_NOTRAIL%" -Quiet -Force
    )
    set "SKIP_SMART_RELAUNCH=0"
    echo.%HERE%| find /I "claude-code-sepidz" >nul && set "SKIP_SMART_RELAUNCH=1"
    echo.%HERE%| find /I "Claude-Connect-Sepidz" >nul && set "SKIP_SMART_RELAUNCH=1"
    if "!SKIP_SMART_RELAUNCH!"=="0" if exist "%USERPROFILE%\Desktop\Claude-Connect\connect.bat" (
        echo.
        echo  [X] OUTDATED scripts in this folder - opening Desktop\Claude-Connect ...
        echo.
        set "CLAUDE_CONNECT_SKIP_HEAL=1"
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $dir=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'; $bat=Join-Path $dir 'connect.bat'; Start-Process -FilePath $bat -WorkingDirectory $dir -WindowStyle Hidden; exit 0 } catch { exit 1 }"
        if not errorlevel 1 exit /b 0
    )
    echo.
    echo  [X] OUTDATED scripts in this folder.
    if "!HERE_IS_SEPIDZ!"=="1" (
        echo      Fix: restore this Sepidz package folder, then run:
        echo    %HERE%connect.bat
    ) else (
        echo      Fix: run connect.bat from:
        echo    %USERPROFILE%\Desktop\Claude-Connect\connect.bat
    )
    echo.
    echo  This folder: %HERE%
    echo.
    pause
    exit /b 1
)

REM Pauses in this launcher: OUTDATED block only (pause+exit /b 1). Update paths never pause.
REM Multi-UI (max 10): connect-boot.ps1 acquires Global\ClaudeConnect#N THEN runs connect.ps1 (no probe/release TOCTOU).
echo.
echo   Starting Claude Connect - accept UAC (Yes) if prompted...
echo.
REM Detach UI so this CMD is not stuck waiting on the whole session.
start "" /D "%HERE_NOTRAIL%" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect-boot.ps1" %*
exit /b 0

