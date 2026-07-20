$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'smart@192.168.210.240'
$title = 'SMART SUDO REQUIRED - type Linux password then Enter'
$remote = 'chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh && sudo bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip; echo EXIT:$?; read -p "Press Enter to close..."'
$ssh = "ssh -tt -o ControlMaster=no -i `"$key`" -o ConnectTimeout=15 $target `"$remote`""
Start-Process cmd.exe -ArgumentList @('/c', "title $title && color 4f && echo. && echo ===== ENTER SMART SERVER SUDO PASSWORD ===== && echo. && $ssh && pause")
Write-Host 'Opened Smart sudo window. Polling for 20260715.18 ...' -ForegroundColor Yellow
$cmd = 'echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt); EL=/usr/local/share/claude-client/editor-launch.ps1; echo preserve=$(grep -c preserve_open_windows "$EL"); echo force=$(grep -c pre_launch_agent_or_new_window "$EL"); echo retry=$(grep -c LAUNCH_RETRY_NO_KILL "$EL")'
$a = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=8',$target,$cmd)
for ($i=1; $i -le 36; $i++) {
  Start-Sleep -Seconds 5
  $o = Join-Path $env:TEMP 'smart-poll2.out'
  $p = Start-Process ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError (Join-Path $env:TEMP 'smart-poll2.err')
  [void]$p.WaitForExit(10000)
  $lines = @(Get-Content $o -EA SilentlyContinue)
  Write-Host ("[$i] " + ($lines -join ' | '))
  if (($lines -join ' ') -match 'version=20260715\.18') {
    Write-Host 'SMART DEPLOY OK' -ForegroundColor Green
    exit 0
  }
}
Write-Host 'SMART STILL NEEDS SUDO' -ForegroundColor Red
exit 1
