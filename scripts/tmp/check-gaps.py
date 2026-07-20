from pathlib import Path
# Win silent function end - is it complete?
ps1 = Path('scripts/client/connect-ui.ps1').read_text(encoding='utf-8')
start = ps1.find('function Invoke-ConnectSilentUpdateCheck')
end = ps1.find('function Write-ConnectSessionOpenSummary')
print('WIN SILENT BLOCK LEN', end-start)
print(ps1[start:end][-800:])
print('====')
sh = Path('scripts/client/connect-ui.sh').read_text(encoding='utf-8')
start = sh.find('invoke_connect_silent_update_check()')
# find next function at column 0
import re
m = re.search(r'\n[a-zA-Z_][a-zA-Z0-9_]*\(\) \{', sh[start+10:])
end = start+10+m.start() if m else start+2000
print('SH SILENT BLOCK:')
print(sh[start:end])
print('==== QUIET in mac update ====')
up = Path('scripts/client/mac/connect-update.sh').read_text(encoding='utf-8')
print('QUIET refs', up.count('CLAUDE_CONNECT_UPDATE_QUIET'))
# show msg helper if any
for i,l in enumerate(up.splitlines(),1):
    if 'QUIET' in l or l.startswith('_msg') or 'printf' in l and 'Update' in l:
        if i<280:
            print(f'{i}:{l}')
