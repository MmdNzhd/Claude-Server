$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
function Probe($label,$target) {
  Write-Output "=== $label ==="
  $cmd = 'echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt); EL=/usr/local/share/claude-client/editor-launch.ps1; echo preserve=$(grep -c preserve_open_windows "$EL"); echo force=$(grep -c pre_launch_agent_or_new_window "$EL"); echo retry=$(grep -c LAUNCH_RETRY_NO_KILL "$EL"); ls ~/claude-client-bundle-deploy 2>/dev/null | head -5'
  $a = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=10','-o','StrictHostKeyChecking=accept-new',$target,$cmd)
  $out = Join-Path $env:TEMP "chk-$label.out"
  $err = Join-Path $env:TEMP "chk-$label.err"
  $p = Start-Process -FilePath ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $p.WaitForExit(20000)) { try{$p.Kill()}catch{}; Write-Output 'TIMEOUT'; return }
  Write-Output ("exit=" + $p.ExitCode)
  if (Test-Path $out) { Get-Content $out }
  if (Test-Path $err) { $e=Get-Content $err; if($e){ Write-Output 'STDERR:'; $e } }
}
Probe 'SMART' 'smart@192.168.210.240'
Probe 'SEPIDZ' 'sepidz@192.168.250.70'
Write-Output '=== WINDOWS_PROCS ==='
Get-Process | Where-Object { $_.ProcessName -match '^(ssh|cmd|powershell)$' } | Select-Object Id,ProcessName,StartTime | Format-Table | Out-String
