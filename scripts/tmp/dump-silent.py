from pathlib import Path
import re
p = Path('scripts/client/connect-ui.ps1')
text = p.read_text(encoding='utf-8', errors='replace')
for pat in ['Get-ConnectSessionId','Write-ConnectSessionIndex','SESSION_FILTER','Invoke-ConnectSilentUpdateCheck','UPDATE_SILENT','sessions.index']:
    print(pat, '->', len(re.findall(re.escape(pat), text)))
# find function Invoke-ConnectSilentUpdateCheck
idx = text.find('function Invoke-ConnectSilentUpdateCheck')
print('Invoke fn at', idx)
if idx>=0:
    print(text[idx:idx+2500])
print('==== init end ====')
print(text[text.find('function Initialize-ConnectLog'):text.find('function Initialize-ConnectLog')+2200])
print('==== sh ====')
sh = Path('scripts/client/connect-ui.sh').read_text(encoding='utf-8', errors='replace')
for pat in ['invoke_connect_silent_update','SESSION_FILTER','sessions.index','CLAUDE_CONNECT_RUN_ID','CONNECT_SESSION_ID']:
    print(pat, '->', len(re.findall(re.escape(pat), sh)))
idx = sh.find('invoke_connect_silent_update')
print('sh silent at', idx)
if idx>=0:
    print(sh[max(0,idx-200):idx+1800])
idx = sh.find('init_connect_log')
print('init_connect_log:')
print(sh[idx:idx+1200])
