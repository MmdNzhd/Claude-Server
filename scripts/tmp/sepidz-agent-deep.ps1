$ErrorActionPreference='Continue'
$key=Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target='sepidz@192.168.250.70'

# write remote script via scp to avoid quoting hell
$remote = @'
#!/bin/bash
set -e
echo "=== HOST ==="
hostname; whoami; date -u
echo "=== GOLDEN ==="
ls -la /etc/cursor-auth/golden/
echo "exported_at=$(cat /etc/cursor-auth/golden/exported-at 2>/dev/null)"
echo "source_host=$(cat /etc/cursor-auth/golden/source-host 2>/dev/null)"
echo "machine_id=$(cat /etc/cursor-auth/golden/machine-id.txt 2>/dev/null)"
python3 <<'PY'
import json,os,time,base64,datetime
p='/etc/cursor-auth/golden/auth.json'
d=json.load(open(p))
keys=sorted(d.keys())
print('auth_keys',keys)
# find tokens without printing secrets
access=None; refresh=None
for k,v in d.items():
    lk=k.lower()
    if 'access' in lk and isinstance(v,str) and len(v)>20: access=(k,v)
    if 'refresh' in lk and isinstance(v,str) and len(v)>20: refresh=(k,v)
print('has_access',bool(access),'access_key',access[0] if access else None,'access_len',len(access[1]) if access else 0)
print('has_refresh',bool(refresh),'refresh_key',refresh[0] if refresh else None,'refresh_len',len(refresh[1]) if refresh else 0)
# try decode JWT payload exp if access looks like jwt
if access and access[1].count('.')==2:
    try:
        payload=access[1].split('.')[1]
        pad='='*(-len(payload)%4)
        data=json.loads(base64.urlsafe_b64decode(payload+pad))
        exp=data.get('exp')
        if exp:
            print('access_exp_utc',datetime.datetime.utcfromtimestamp(exp).isoformat()+'Z')
            print('access_expired',exp < time.time())
            print('access_exp_in_sec',int(exp-time.time()))
        print('jwt_claims',sorted([k for k in data.keys() if k in ('sub','email','scope','aud','iss') or 'email' in k.lower()]) )
        for k in data:
            if 'email' in k.lower():
                print('jwt_email',data[k]); break
    except Exception as e:
        print('jwt_decode_err',type(e).__name__)
sk='/etc/cursor-auth/golden/state-keys.json'
if os.path.exists(sk):
    s=json.load(open(sk))
    print('state_keys_count',len(s) if isinstance(s,dict) else type(s).__name__)
    if isinstance(s,dict):
        interesting=[k for k in s if any(x in k.lower() for x in ('auth','token','email','membership','subscription','shouldlogout'))]
        print('state_interesting',interesting[:30])
        for k in interesting:
            v=s[k]
            if isinstance(v,str) and len(v)>40: print(k,'=<redacted len',len(v),'>')
            else: print(k,'=',v)
PY
echo "=== REFRESH LOG ==="
if [ -f /var/log/cursor-auth-refresh.log ]; then tail -40 /var/log/cursor-auth-refresh.log; else echo no_log; fi
echo "=== CRON ==="
ls -la /etc/cron.d/cursor-auth* 2>/dev/null || true
cat /etc/cron.d/cursor-auth-refresh 2>/dev/null || true
echo "=== USER SYNC STATE ==="
for u in sepidz farzadb alit aminb hosseinb hosseinm nimaz zahrak smart designer; do
  gs=/home/$u/.config/Cursor/User/globalStorage
  if [ -d "$gs" ]; then
    echo -n "USER $u "
    ls -la "$gs/state.vscdb" 2>/dev/null | awk '{print "state",$5,$6,$7,$8}'
    # check if cursorAuth keys present via python sqlite if available
    if [ -f "$gs/state.vscdb" ]; then
      python3 - <<PY
import sqlite3,os
p="$gs/state.vscdb"
try:
  c=sqlite3.connect(f'file:{p}?mode=ro',uri=True)
  cur=c.cursor()
  # ItemTable key/value typical
  tables=[r[0] for r in cur.execute("select name from sqlite_master where type='table'")]
  keycol=None
  for t in tables:
    cols=[r[1] for r in cur.execute(f'pragma table_info({t})')]
    if 'key' in cols and 'value' in cols:
      rows=list(cur.execute(f"select key from {t} where key like '%cursorAuth%' or key like '%email%' or key like '%shouldLogout%' limit 30"))
      if rows:
        print(' ',t,'authish_keys',[r[0] for r in rows])
  c.close()
except Exception as e:
  print('  sqlite_err',type(e).__name__,e)
PY
    fi
  fi
done
'@
$tmp = Join-Path $env:TEMP 'sepidz-agent-deep.sh'
Set-Content -Path $tmp -Value $remote -Encoding ASCII
$a1=@('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=15',$target,"cat > /tmp/sepidz-agent-deep.sh && chmod +x /tmp/sepidz-agent-deep.sh")
# scp instead
& scp -o ControlMaster=no -i $key -o BatchMode=yes -o ConnectTimeout=15 -q $tmp "${target}:/tmp/sepidz-agent-deep.sh"
Write-Output "scp_exit=$LASTEXITCODE"
$a=@('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=20',$target,'bash /tmp/sepidz-agent-deep.sh')
$o=Join-Path $env:TEMP 'sepidz-deep.out'; $e=Join-Path $env:TEMP 'sepidz-deep.err'
$p=Start-Process ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
[void]$p.WaitForExit(60000)
Write-Output ("ssh_exit="+$p.ExitCode)
Get-Content $o -EA SilentlyContinue
Write-Output '---stderr---'
Get-Content $e -EA SilentlyContinue | Select-Object -First 30
