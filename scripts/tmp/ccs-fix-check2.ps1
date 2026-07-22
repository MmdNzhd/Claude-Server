$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Write-Host '=== .52 sessions ==='
Select-String -Path $log -Pattern 'CONNECT_VERSION=20260721\.52' | Select-Object -Last 20 | ForEach-Object { $_.Line }
Write-Host '=== after 19:40 FAIL/ERROR/WARN key ==='
Get-Content $log | Where-Object { $_ -match '^\[2026-07-21 19:(4|5)' -or $_ -match '^\[2026-07-21 20:' } | Where-Object { $_ -match 'FAIL|ERROR|PROXY_|SIDECAR|CLEAR|LAUNCH_KILL|Exception|cannot|Parse|DOTSOURCE|UPDATE_' } | Select-Object -Last 50
Write-Host '=== Desktop connect.ps1 version + sidecar ==='
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
Write-Host ("ver={0}" -f (Get-Content (Join-Path $desk 'connect-version.txt') -Raw).Trim())
Write-Host ("sidecar={0}" -f (Test-Path (Join-Path $desk 'cursor-proxy-sidecar.ps1')))
Write-Host ("connectHasSidecarDot={0}" -f ((Get-Content (Join-Path $desk 'connect.ps1') -Raw) -match 'cursor-proxy-sidecar'))
# Try starting sidecar briefly
. .\scripts\client\git-mode.ps1
. .\scripts\client\windows\cursor-proxy-sidecar.ps1
try {
  $r = Start-CursorProxySidecar
  Write-Host ("SIDECAR_START result={0}" -f $r)
} catch {
  Write-Host ("SIDECAR_ERR {0}" -f $_.Exception.Message)
}
foreach ($p in 18999,18998,19080,19180) {
  $ok = $false
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect([System.Net.IPAddress]::Loopback, $p, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(300)
    if ($ok) { try { $c.EndConnect($iar) } catch { $ok = $false } }
    $c.Close()
  } catch { $ok = $false }
  Write-Host ("PORT {0} open={1}" -f $p, $ok)
}
