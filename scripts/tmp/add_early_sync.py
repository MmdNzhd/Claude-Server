from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')
t = p.read_text(encoding='utf-8')
needle = 'Sanitize-SshAliasConfig -CfgPath $sshCfg -AliasName $Alias\n'
insert = needle + 'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }  # ship BOOTSTRAP/UPDATE + session so far\n'
# only the main path one (sshCfg lowercase) - may appear twice
count = t.count(needle)
print('sanitize count', count)
if 'ship BOOTSTRAP/UPDATE' not in t:
    t = t.replace(needle, insert, 1)  # first occurrence after main setup
    p.write_text(t, encoding='utf-8', newline='\n')
    print('early sync inserted')
else:
    print('already')
