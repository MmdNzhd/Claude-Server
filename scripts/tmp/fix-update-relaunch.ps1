Set-Location D:\Smart\Claude-Code-Server
$utf8 = New-Object System.Text.UTF8Encoding $false
$path = Resolve-Path 'scripts/client/windows/connect.bat'
$t = [IO.File]::ReadAllText($path)

# Old nested call keeps the same console open ("باز میشه بسته نمیشه")
$old = @"
            echo.
            echo   Restarting with updated files...
            echo.
            call "%~f0" %*
            exit /b !errorlevel!
"@
$new = @"
            echo.
            echo   Restarting with updated files...
            echo.
            REM Spawn a fresh process then CLOSE this console (call/exit /b left the
            REM update window open on top of Connect — felt like "opens but won't close").
            start "" /D "%HERE%" "%~f0" %*
            exit 0
"@

# normalize CRLF for match
$tn = $t -replace "`r`n","`n"
$oldn = $old -replace "`r`n","`n"
$newn = $new -replace "`r`n","`n"
if ($tn.Contains($oldn)) {
  $tn = $tn.Replace($oldn, $newn)
  [IO.File]::WriteAllText($path, ($tn -replace "`n","`r`n"), $utf8)
  Write-Host 'OK connect.bat start+exit relaunch' -ForegroundColor Green
} elseif ($tn -match 'start "" /D "%HERE%" "%~f0"') {
  Write-Host 'SKIP already fixed' -ForegroundColor Yellow
} else {
  Write-Host 'MISS exact block — dumping:' -ForegroundColor Red
  Select-String -Path $path -Pattern 'Restarting with updated' -Context 0,6
  exit 1
}

# Bump patch version so auto-update picks this bat fix
$verPath = 'scripts/client/windows/connect-version.txt'
$cur = (Get-Content $verPath -Raw).Trim()
if ($cur -match '^(\d{8})\.(\d+)$') {
  $next = "{0}.{1}" -f $Matches[1], ([int]$Matches[2] + 1)
} else { $next = '20260720.13' }
Set-Content $verPath $next -Encoding ascii -NoNewline
Set-Content $verPath ($next + "`n") -Encoding ascii
# sync connect.ps1 + mac
$win = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/windows/connect.ps1'))
$win2 = [regex]::Replace($win, "(?m)^\`$script:ConnectVersion = '20260720\.\d+'\s*$", "`$script:ConnectVersion = '$next'")
if ($win2 -eq $win) { throw 'connect.ps1 version sync failed' }
[IO.File]::WriteAllText((Resolve-Path 'scripts/client/windows/connect.ps1'), $win2, $utf8)
$mac = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/mac/connect.sh'))
$mac2 = [regex]::Replace($mac, "CONNECT_VERSION='20260720\.\d+'", "CONNECT_VERSION='$next'")
[IO.File]::WriteAllText((Resolve-Path 'scripts/client/mac/connect.sh'), $mac2, $utf8)
try { Set-Content 'scripts/client/mac/connect-version.txt' ($next + "`n") -Encoding ascii } catch { Write-Host "mac ver file locked: $_" }
Write-Host "BUMPED to $next"

# show resulting bat block
Select-String -Path $path -Pattern 'Restarting with updated' -Context 0,8 | ForEach-Object {
  $_.Context.PreContext + $_.Line + $_.Context.PostContext | ForEach-Object { Write-Host $_ }
}

# parse connect.ps1
$tok=$null;$err=$null
$null=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts/client/windows/connect.ps1'),[ref]$tok,[ref]$err)
if ($err -and $err.Count) { $err | %{ Write-Host $_.Message -ForegroundColor Red }; exit 1 }
Write-Host 'PARSE OK' -ForegroundColor Green
