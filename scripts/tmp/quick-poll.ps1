$key=Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$cmd='echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt); EL=/usr/local/share/claude-client/editor-launch.ps1; echo preserve=$(grep -c preserve_open_windows "$EL"); echo force=$(grep -c pre_launch_agent_or_new_window "$EL")'
foreach ($pair in @(@('SMART','smart@192.168.210.240'),@('SEPIDZ','sepidz@192.168.250.70'))) {
  $a=@('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=8',$pair[1],$cmd)
  $o=Join-Path $env:TEMP ('q-'+$pair[0]+'.out')
  $p=Start-Process ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError (Join-Path $env:TEMP 'q.err')
  [void]$p.WaitForExit(12000)
  Write-Output ($pair[0] + ': ' + ((Get-Content $o -EA SilentlyContinue) -join ' | '))
}
