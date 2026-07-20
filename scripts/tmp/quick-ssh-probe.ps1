$ErrorActionPreference='Continue'
foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName='ssh'
  $psi.Arguments="-o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 $t `"echo OK; tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt`""
  $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
  $p=[Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(18000)) { try{$p.Kill()}catch{}; Write-Host "$t TIMEOUT" }
  else {
    $o=$p.StandardOutput.ReadToEnd().Trim()
    $e=$p.StandardError.ReadToEnd().Trim()
    Write-Host "$t exit=$($p.ExitCode) out=$o err=$e"
  }
}
$ssh = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'")
Write-Host ("total_ssh=" + $ssh.Count)
