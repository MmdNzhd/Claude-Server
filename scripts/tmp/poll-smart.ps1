$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'smart@192.168.210.240'
$cmd = 'echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt); EL=/usr/local/share/claude-client/editor-launch.ps1; echo preserve=$(grep -c preserve_open_windows "$EL"); echo force=$(grep -c pre_launch_agent_or_new_window "$EL")'
$a = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=8',$target,$cmd)
for ($i=1; $i -le 24; $i++) {
  $out = Join-Path $env:TEMP 'poll-s.out'
  $p = Start-Process -FilePath ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError (Join-Path $env:TEMP 'poll-s.err')
  [void]$p.WaitForExit(10000)
  $lines = @(Get-Content $out -EA SilentlyContinue)
  Write-Output ("[$i] " + ($lines -join ' | '))
  if ($lines -match 'version=20260715\.18') { Write-Output 'SUCCESS'; exit 0 }
  Start-Sleep -Seconds 5
}
Write-Output 'STILL_WAITING'
exit 1
