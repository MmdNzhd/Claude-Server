$ErrorActionPreference='Continue'
# Keep processes that look like the connect tunnel (RemoteForward / -R / claude-server alias / ControlMaster)
$kept = @()
$killed = @()
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" | ForEach-Object {
  $cmd = $_.CommandLine
  if (-not $cmd) { return }
  $isTunnel = ($cmd -match 'RemoteForward|\s-R\s|claude-server|ControlMaster=yes|ControlPath')
  $isServerProbe = ($cmd -match '192\.168\.(210\.240|250\.70)')
  if ($isServerProbe -and -not $isTunnel) {
    & taskkill /F /PID $_.ProcessId 2>$null | Out-Null
    $killed += $_.ProcessId
  } else {
    $kept += ("KEEP $($_.ProcessId): " + $cmd.Substring(0,[Math]::Min(100,$cmd.Length)))
  }
}
Write-Host ("killed_count=" + $killed.Count)
Write-Host ("killed=" + ($killed -join ','))
$kept | ForEach-Object { Write-Host $_ }
Start-Sleep 3
# Also kill stuck cmd.exe sudo helpers
Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
  Where-Object { $_.CommandLine -match 'Claude bundle install|install-client-bundle' } |
  ForEach-Object { taskkill /F /PID $_.ProcessId 2>$null | Out-Null; Write-Host "killed cmd $($_.ProcessId)" }

Write-Host '=== retry ssh after cleanup ==='
Start-Sleep 5
foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName='ssh'; $psi.Arguments="-o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 $t hostname"
  $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
  $p=[Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(20000)) { try{$p.Kill()}catch{}; Write-Host "$t TIMEOUT" }
  else { Write-Host "$t exit=$($p.ExitCode) out=$($p.StandardOutput.ReadToEnd().Trim()) err=$($p.StandardError.ReadToEnd().Trim())" }
}
