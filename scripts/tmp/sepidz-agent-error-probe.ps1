$ErrorActionPreference='Continue'
$key=Join-Path $env:USERPROFILE '.ssh\claude_laptop'
function R($label,$target,$cmd){
  Write-Output "=== $label ==="
  $a=@('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=12',$target,$cmd)
  $o=Join-Path $env:TEMP "sep-$label.out"; $e=Join-Path $env:TEMP "sep-$label.err"
  $p=Start-Process ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if(-not $p.WaitForExit(25000)){ try{$p.Kill()}catch{}; Write-Output 'TIMEOUT'; return }
  Write-Output ("exit="+$p.ExitCode)
  if(Test-Path $o){ Get-Content $o }
  $err=Get-Content $e -EA SilentlyContinue; if($err){ Write-Output 'STDERR:'; $err | Select-Object -First 10 }
}
$cmd=@'
echo host=$(hostname) user=$(whoami)
echo '--- golden ---'
ls -la /etc/cursor-auth/golden/ 2>/dev/null | head -20
echo exported_at=$(cat /etc/cursor-auth/golden/exported-at 2>/dev/null)
echo '--- sample user cursor auth ---'
for u in sepidz farzadb alit aminb hosseinb designer smart; do
  f=/home/$u/.config/Cursor/User/globalStorage/storage.json
  s=/home/$u/.config/Cursor/User/globalStorage/state.vscdb
  if [ -f "$s" ] || [ -f "$f" ]; then
    echo "USER $u state=$( [ -f "$s" ] && ls -la "$s" | awk '{print $5,$6,$7,$8,$9}' || echo none ) storage=$( [ -f "$f" ] && echo yes || echo no)"
  fi
done
echo '--- recent cursor/auth logs if any ---'
ls -lt /var/log/cursor* 2>/dev/null | head -5
grep -R "unexpected error\|Request ID\|f0f5a8ca\|agent" /var/log/claude-auth.log 2>/dev/null | tail -5
# check if refresh cron healthy
ls -la /etc/cron.d/cursor-auth* 2>/dev/null
'@
R 'SEPIDZ' 'sepidz@192.168.250.70' $cmd
R 'SMART' 'smart@192.168.210.240' $cmd
