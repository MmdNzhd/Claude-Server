$ErrorActionPreference='Continue'
$key=Join-Path $env:USERPROFILE '.ssh\claude_laptop'
function Probe-Remote([string]$Label,[string]$Target){
  Write-Output "=== $Label ==="
  $cmd = @'
echo host=$(hostname) user=$(whoami)
echo '--- golden ---'
ls -la /etc/cursor-auth/golden/ 2>/dev/null | head -20
echo exported_at=$(cat /etc/cursor-auth/golden/exported-at 2>/dev/null)
echo auth_json_keys=$(python3 -c "import json;d=json.load(open('/etc/cursor-auth/golden/auth.json'));print(','.join(sorted(d.keys())))" 2>/dev/null)
echo has_access=$(python3 -c "import json;d=json.load(open('/etc/cursor-auth/golden/auth.json'));print('yes' if d.get('accessToken') or d.get('cursorAuth/accessToken') else 'no')" 2>/dev/null)
echo has_refresh=$(python3 -c "import json;d=json.load(open('/etc/cursor-auth/golden/auth.json'));print(any('refresh' in k.lower() for k in d))" 2>/dev/null)
echo '--- refresh log ---'
tail -20 /var/log/cursor-auth-refresh.log 2>/dev/null || echo no_refresh_log
echo '--- users with Cursor state ---'
for u in $(ls /home 2>/dev/null); do
  s=/home/$u/.config/Cursor/User/globalStorage/state.vscdb
  if [ -f "$s" ]; then
    echo "USER $u state_bytes=$(stat -c%s "$s" 2>/dev/null) mtime=$(stat -c%y "$s" 2>/dev/null | cut -d. -f1)"
  fi
done
echo '--- claude settings sample (farzadb/sepidz) ---'
for u in sepidz farzadb; do
  f=/home/$u/.claude/settings.json
  if [ -f "$f" ]; then echo "USER $u has settings"; python3 -c "import json;d=json.load(open('$f'));print('oauth',bool(d.get('env',{}).get('CLAUDE_CODE_OAUTH_TOKEN')));print('plugins',list((d.get('enabledPlugins') or d.get('plugins') or {}).keys())[:5] if isinstance(d.get('enabledPlugins') or d.get('plugins'),dict) else 'n/a')" 2>/dev/null; fi
done
'@
  $a=@('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=15',$Target,$cmd)
  $o=Join-Path $env:TEMP "sep2-$Label.out"; $e=Join-Path $env:TEMP "sep2-$Label.err"
  $p=Start-Process ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if(-not $p.WaitForExit(30000)){ try{$p.Kill()}catch{}; Write-Output 'TIMEOUT'; return }
  Write-Output ("exit="+$p.ExitCode)
  Get-Content $o -EA SilentlyContinue
  $err=Get-Content $e -EA SilentlyContinue; if($err){ Write-Output 'STDERR:'; $err | Select-Object -First 8 }
}
Probe-Remote 'SEPIDZ' 'sepidz@192.168.250.70'
# docs snippet
Write-Output '=== DOC HINT ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\docs\client-connect.md' -Pattern 'Chat cannot send|Reload Window|Agent' |
  ForEach-Object { $_.Line.Trim() }
