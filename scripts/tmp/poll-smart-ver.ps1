$ErrorActionPreference='Continue'
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match 'finish-smart-sure' } |
  ForEach-Object { "python_pid=$($_.ProcessId)" }
python -u -c @"
import pathlib, paramiko
KEY=pathlib.Path.home()/'.ssh'/'id_ed25519'
c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('192.168.210.240', username='smart', key_filename=str(KEY), timeout=15, allow_agent=False, look_for_keys=False)
_,o,_=c.exec_command(\"tr -d '\\\\r\\\\n' < /usr/local/share/claude-client/connect-version.txt\")
print('SMART_VER='+o.read().decode().strip())
c.close()
"@
