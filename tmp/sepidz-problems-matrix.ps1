#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-Location 'D:\Smart\Claude-Code-Server'
$raw=Get-Content 'publish\sepidz-deploy.local.ps1' -Raw
$pw=[regex]::Match($raw,'(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$target='sepidz@192.168.250.70'
$remote='/home/sepidz/prob.sh'
$local=Join-Path $env:TEMP ('prob-'+[guid]::NewGuid().ToString('n')+'.sh')
$sh=@'
#!/bin/bash
set +e
echo === GOLDEN PERMS ===
ls -la /etc/cursor-auth/golden/ 2>&1 | head -20
getent group cursorauth 2>&1
id farzadb 2>&1 | head -1
id hosseinb 2>&1 | head -1
echo === VERSIONS ALL USERS ===
for f in /home/*/.claude/logs/connect-20260722.log; do
  [ -f "$f" ] || continue
  u=$(echo "$f" | cut -d/ -f3)
  echo "-- $u --"
  grep -E 'CONNECT_VERSION=|ScriptDir=|local_exe_drift|BOOTSTRAP|UPDATE:|BUILD_ID=' "$f" | sed 's/\r$//' | sort -u | head -40
done
echo === SIGNATURE COUNTS ALL ===
python3 - <<'PY'
import re,collections,glob,os
keys=collections.Counter()
by_user=collections.defaultdict(collections.Counter)
for path in glob.glob('/home/*/.claude/logs/connect-20260722.log'):
  u=path.split('/')[2]
  for line in open(path,errors='replace'):
    for pat in [
      r'VERDICT_CODE=([A-Z_]+)',
      r'FAIL\s+([A-Z_]+)',
      r'AUTH ERROR\s+(\S+)',
      r'(LOG_SYNC_FAIL|foreign_peer|PUSH_CONF blocked|TUNNEL_DROP|need_mount|SSHFS_NOT_MOUNTED|swap_fail|PROXY_HEALTH ok=0|SIDECAR_ENSURE|machineid_file_mismatch|Connection refused|SESSION_STATUS=BROKEN|OUTDATED_SCRIPTS|UPDATE_UNHANDLED|local_exe_drift|mkdir_timeout)',
    ]:
      for m in re.finditer(pat,line):
        k=m.group(0) if m.lastindex is None else (m.group(0) if 'VERDICT' not in pat and 'FAIL' not in pat and 'AUTH' not in pat else m.group(0))
        # normalize
        if 'VERDICT_CODE=' in pat: k='VERDICT:'+m.group(1)
        elif 'FAIL' in pat and pat.startswith('FAIL'): k='FAIL:'+m.group(1)
        elif 'AUTH ERROR' in pat: k='AUTH:'+m.group(1)
        else: k=m.group(1) if m.lastindex else m.group(0)
        keys[k]+=1; by_user[u][k]+=1
print('TOTAL:')
for k,n in keys.most_common(50):
  print(f'{n:5d} {k}')
print('BY_USER:')
for u in sorted(by_user):
  top=', '.join(f'{k}:{n}' for k,n in by_user[u].most_common(12))
  print(f'{u}: {top}')
PY
echo === LE AUDIT TODAY ===
ls /home/*/.claude/logs/laptop-exec-20260722.log 2>/dev/null
echo __DONE__
'@
[IO.File]::WriteAllText($local,$sh.Replace("`r`n","`n"),(New-Object Text.UTF8Encoding $false))
scp -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -q $local ($target+':'+$remote)|Out-Null
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName='ssh.exe'; $psi.Arguments="-o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no $target `"sudo -S -p '' bash $remote; rm -f $remote`""
$psi.UseShellExecute=$false; $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
$p=[Diagnostics.Process]::Start($psi); $p.StandardInput.WriteLine($pw); $p.StandardInput.Close()
$out=$p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(120000)
Write-Output $out
Remove-Item $local -Force -EA SilentlyContinue
