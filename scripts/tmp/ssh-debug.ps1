$ErrorActionPreference='Continue'
Write-Host '=== remaining ssh to servers ==='
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match '192\.168\.(210\.240|250\.70)' } |
  ForEach-Object {
    Write-Host ("PID=$($_.ProcessId) CMD=$($_.CommandLine.Substring(0,[Math]::Min(180,$_.CommandLine.Length)))")
    # force kill again
    & taskkill /F /PID $_.ProcessId 2>&1 | Out-Null
  }
Start-Sleep 2
$left = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match '192\.168\.(210\.240|250\.70)' })
Write-Host ("left_after_taskkill=" + $left.Count)

# Show ALL ssh.exe briefly
Write-Host '=== all ssh.exe count ==='
$all = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'")
Write-Host ("total_ssh=" + $all.Count)

Write-Host '=== verbose ssh smart (12s) ==='
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh'
$psi.Arguments = '-vvv -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 smart@192.168.210.240 echo PONG'
$psi.UseShellExecute = $false
$psi.RedirectStandardError = $true
$psi.RedirectStandardOutput = $true
$psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
if (-not $p.WaitForExit(20000)) { try{$p.Kill()}catch{}; Write-Host 'HARD_TIMEOUT' }
else { Write-Host ("exit=$($p.ExitCode)") }
$err = $p.StandardError.ReadToEnd()
$out = $p.StandardOutput.ReadToEnd()
Write-Host 'OUT:' $out
Write-Host 'ERR_TAIL:'
($err -split "`n") | Select-Object -Last 40 | ForEach-Object { $_ }
