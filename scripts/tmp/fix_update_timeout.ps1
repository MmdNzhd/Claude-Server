$ErrorActionPreference='Continue'
# Kill wrong Smart connect
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'claude-code-client-.*connect\.ps1' } |
  ForEach-Object {
    Write-Host ("kill Smart-client PID=" + $_.ProcessId)
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
  }

$p = 'scripts\client\windows\connect-update.ps1'
$t = Get-Content $p -Raw
# Faster version/manifest cat: 8s not 20s
$t2 = $t.Replace(
  '$r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 20000 -RequireStdout',
  '$r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 8000 -RequireStdout'
)
if ($t2 -eq $t) { Write-Host 'WARN: timeout replace miss' } else { Write-Host 'OK: cat timeout 8s' }

# For Sepidz IP, try service account FIRST when primary fails fast - also reorder Resolve to try sepidz sooner
# Improve Resolve-UpdateEndpoint: on 250.70, if primary is smart@ and fails, already falls back.
# Add: when IP is 250.70, try sepidz@ in parallel conceptually by preferring conf user but with short timeout (done).

# Also: if Get-RemoteUserFromConf returns smart but first SSH fails, don't wait full - already 8s now.

Set-Content -LiteralPath $p -Value $t2 -Encoding UTF8 -NoNewline
# preserve final newline
[IO.File]::AppendAllText((Resolve-Path $p), "`n")

# bump 17 -> 18
$ver='20260719.18'
Set-Content scripts\client\windows\connect-version.txt $ver
if (Test-Path scripts\client\mac\connect-version.txt) { Set-Content scripts\client\mac\connect-version.txt $ver }
$cp = Get-Content scripts\client\windows\connect.ps1 -Raw
$cp2 = $cp -replace "ConnectVersion = '20260719\.17'", "ConnectVersion = '$ver'"
if ($cp2 -eq $cp) { throw 'version bump fail' }
[IO.File]::WriteAllText((Resolve-Path scripts\client\windows\connect.ps1), $cp2.TrimEnd() + "`n")
Write-Host "bumped $ver"
