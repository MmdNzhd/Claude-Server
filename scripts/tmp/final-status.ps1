$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
function Probe($n,$t) {
  $cmd = 'echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt); EL=/usr/local/share/claude-client/editor-launch.ps1; echo preserve=$(grep -c preserve_open_windows "$EL"); echo force=$(grep -c pre_launch_agent_or_new_window "$EL"); echo retry=$(grep -c LAUNCH_RETRY_NO_KILL "$EL"); echo force_calls=$(grep -Ec "Stop-CursorServerProfileTreeIfNeeded.*-Force" "$EL")'
  $a=@('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=10',$t,$cmd)
  $o=Join-Path $env:TEMP "fs-$n.out"
  $p=Start-Process ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError (Join-Path $env:TEMP "fs-$n.err")
  [void]$p.WaitForExit(15000)
  Write-Output "=== $n ==="
  Get-Content $o -EA SilentlyContinue
}
Probe 'SMART' 'smart@192.168.210.240'
Probe 'SEPIDZ' 'sepidz@192.168.250.70'
Write-Output '=== LOCAL_HELPERS ==='
@(
  'D:\Smart\Claude-Code-Server\publish\smart-deploy.local.ps1',
  'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1'
) | ForEach-Object { if (Test-Path $_) { Write-Output "EXISTS $_" } else { Write-Output "MISS $_" } }
