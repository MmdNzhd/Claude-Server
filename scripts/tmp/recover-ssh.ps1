$ErrorActionPreference='Continue'
Write-Host '=== Kill ALL ssh to smart/sepidz servers ==='
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match '192\.168\.(210\.240|250\.70)' } |
  ForEach-Object {
    Write-Host ("kill $($_.ProcessId)")
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
  }
Get-Job | Stop-Job -EA SilentlyContinue
Get-Job | Remove-Job -Force -EA SilentlyContinue
Start-Sleep 3
$left = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match '192\.168\.(210\.240|250\.70)' })
Write-Host ("left=" + $left.Count)

Write-Host '=== ping ==='
foreach ($ip in @('192.168.210.240','192.168.250.70')) {
  $p = Test-Connection -ComputerName $ip -Count 2 -Quiet -ErrorAction SilentlyContinue
  Write-Host ("ping $ip = $p")
}

Write-Host '=== wait 10s then ssh smoke ==='
Start-Sleep 10
foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'ssh'
  $psi.Arguments = "-o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 $t echo PONG"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(15000)) {
    try { $p.Kill() } catch {}
    Write-Host ("$t => HARD_TIMEOUT")
  } else {
    $o = $p.StandardOutput.ReadToEnd().Trim()
    $e = $p.StandardError.ReadToEnd().Trim()
    Write-Host ("$t => exit=$($p.ExitCode) out=$o err=$e")
  }
}
