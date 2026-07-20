$ErrorActionPreference='Stop'
python -u -c @"
import pathlib, paramiko, sys
KEY=pathlib.Path.home()/'.ssh'/'id_ed25519'
def ver(host,user):
  c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
  c.connect(host,username=user,key_filename=str(KEY),timeout=15,allow_agent=False,look_for_keys=False)
  _,o,_=c.exec_command(\"tr -d '\\\\r\\\\n' < /usr/local/share/claude-client/connect-version.txt\")
  v=o.read().decode().strip(); c.close(); return v
s=ver('192.168.250.70','sepidz'); m=ver('192.168.210.240','smart')
print('SEPIDZ',s); print('SMART',m)
sys.exit(0 if s=='20260717.3' else 1)
"@
