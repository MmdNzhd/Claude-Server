$ErrorActionPreference='Continue'
Write-Host '=== kill non-tunnel ssh ==='
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" | ForEach-Object {
  $cmd = $_.CommandLine
  if (-not $cmd) { return }
  $isTunnel = ($cmd -match 'RemoteForward|\s-R\s|claude-server|ControlMaster=yes|-N -o ExitOnForwardFailure|-T -D')
  $isServer = ($cmd -match '192\.168\.(210\.240|250\.70)|@192\.168')
  if ($isServer -and -not $isTunnel) {
    taskkill /F /PID $_.ProcessId 2>$null | Out-Null
    Write-Host "killed $($_.ProcessId)"
  }
}
Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
  Where-Object { $_.CommandLine -match 'Claude bundle install|install-client-bundle' } |
  ForEach-Object { taskkill /F /PID $_.ProcessId 2>$null | Out-Null }

Write-Host 'waiting 45s for MaxStartups...'
Start-Sleep -Seconds 45

function Try-Ssh([string]$Target, [string]$RemoteCmd) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName='ssh'
  $psi.Arguments="-o BatchMode=yes -o ConnectTimeout=12 -o ConnectionAttempts=1 -o ServerAliveInterval=3 $Target $RemoteCmd"
  $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
  $p=[Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(25000)) { try{$p.Kill()}catch{}; return @{Ok=$false; Out='TIMEOUT'; Err=''} }
  return @{Ok=($p.ExitCode -eq 0); Out=$p.StandardOutput.ReadToEnd().Trim(); Err=$p.StandardError.ReadToEnd().Trim(); Exit=$p.ExitCode}
}

Write-Host '=== probe ==='
foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  $r = Try-Ssh $t 'echo PONG; tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt'
  Write-Host ("{0} ok={1} exit={2} out={3} err={4}" -f $t, $r.Ok, $r.Exit, $r.Out, $r.Err)
}

# If sepidz works, deploy with password
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$root='D:\Smart\Claude-Code-Server'
$sepid=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'
$smart=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717'

$r = Try-Ssh 'sepidz@192.168.250.70' 'echo PONG'
if ($r.Ok) {
  Write-Host '=== DEPLOY SEPIDZ via deploy-client-bundles ===' -ForegroundColor Green
  & (Join-Path $root 'publish\deploy-client-bundles.ps1') -ProjectRoot $root -SepidClientRoot $sepid -DeploySmart:$false -DeploySepidz:$true
} else {
  Write-Host 'SEPIDZ still unreachable from laptop' -ForegroundColor Red
}

$r2 = Try-Ssh 'smart@192.168.210.240' 'echo PONG'
if ($r2.Ok) {
  Write-Host '=== DEPLOY SMART ===' -ForegroundColor Green
  & (Join-Path $root 'publish\deploy-client-bundles.ps1') -ProjectRoot $root -SmartClientRoot $smart -DeploySmart:$true -DeploySepidz:$false
} else {
  Write-Host 'SMART still unreachable from laptop' -ForegroundColor Red
}
