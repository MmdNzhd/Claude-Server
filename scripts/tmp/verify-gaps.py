from pathlib import Path
import re
checks = [
 ('ps1 Get-ConnectSessionId', 'scripts/client/connect-ui.ps1', 'function Get-ConnectSessionId'),
 ('ps1 SESSION_FILTER', 'scripts/client/connect-ui.ps1', 'SESSION_FILTER'),
 ('ps1 sessions.index', 'scripts/client/connect-ui.ps1', 'sessions.index'),
 ('ps1 SilentUpdate', 'scripts/client/connect-ui.ps1', 'Invoke-ConnectSilentUpdateCheck'),
 ('ps1 export RUN_ID', 'scripts/client/connect-ui.ps1', '$env:CLAUDE_CONNECT_RUN_ID = $script:ConnectSessionId'),
 ('win TUNNEL_DROP auto', 'scripts/client/windows/connect.ps1', 'TUNNEL_DROP reason=auto_reconnect'),
 ('win auto silent', 'scripts/client/windows/connect.ps1', 'Invoke-ConnectSilentUpdateCheck'),
 ('sh connect_session_id', 'scripts/client/connect-ui.sh', 'connect_session_id()'),
 ('sh SESSION_FILTER', 'scripts/client/connect-ui.sh', 'SESSION_FILTER'),
 ('sh reuse RUN_ID', 'scripts/client/connect-ui.sh', 'CLAUDE_CONNECT_RUN_ID'),
 ('sh silent', 'scripts/client/connect-ui.sh', 'invoke_connect_silent_update_check'),
 ('mac bootstrap', 'scripts/client/mac/connect.sh', 'BOOTSTRAP: connect.sh start'),
 ('mac TUNNEL_DROP', 'scripts/client/mac/connect.sh', 'TUNNEL_DROP reason=auto_reconnect'),
 ('git silent auto', 'scripts/client/git-mode.sh', 'invoke_connect_silent_update_check'),
 ('mac update quiet', 'scripts/client/mac/connect-update.sh', 'CLAUDE_CONNECT_UPDATE_QUIET'),
 ('mac update sid stamp', 'scripts/client/mac/connect-update.sh', 'CLAUDE_CONNECT_RUN_ID'),
]
for name, path, needle in checks:
    t = Path(path).read_text(encoding='utf-8', errors='replace')
    print(('PASS' if needle in t else 'FAIL'), name)

# init_connect_log must not force date-$$
sh = Path('scripts/client/connect-ui.sh').read_text(encoding='utf-8')
idx = sh.find('init_connect_log()')
chunk = sh[idx:idx+900]
print('--- init_connect_log chunk ---')
print(chunk)
print('--- mac top ---')
print('\n'.join(Path('scripts/client/mac/connect.sh').read_text(encoding='utf-8').splitlines()[:35]))
