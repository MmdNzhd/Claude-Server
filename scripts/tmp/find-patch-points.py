from pathlib import Path
root = Path('scripts/client')
files = {
  'connect-ui.ps1': root/'connect-ui.ps1',
  'connect.ps1': root/'windows'/'connect.ps1',
  'connect-ui.sh': root/'connect-ui.sh',
  'git-mode.sh': root/'git-mode.sh',
  'connect.sh': root/'mac'/'connect.sh',
  'connect-update.ps1': root/'windows'/'connect-update.ps1',
  'connect-update.sh': root/'mac'/'connect-update.sh',
}
needles = {
  'connect-ui.ps1': ['function Initialize-ConnectLog', 'function Close-ConnectLog', 'function Write-ConnectLog', 'ConnectSessionId'],
  'connect.ps1': ['function Begin-ConnectRecovery', 'connection dropped', 'TUNNEL: connection dropped'],
  'connect-ui.sh': ['init_connect_log', 'CONNECT_SESSION_ID='],
  'git-mode.sh': ['begin_connect_recovery()'],
  'connect.sh': ['_update_script', 'connect-update.sh', 'CLAUDE_CONNECT'],
  'connect-update.ps1': ['[switch]$Quiet', 'Write-UpdateFileLog', 'CLAUDE_CONNECT_RUN_ID'],
  'connect-update.sh': ['_update_file_log', 'printf', 'CLAUDE_CONNECT'],
}
for name, path in files.items():
  text = path.read_text(encoding='utf-8', errors='replace').splitlines()
  print(f'==== {name} ({len(text)} lines) ====')
  for n in needles[name]:
    hits = [(i+1, line.rstrip()) for i, line in enumerate(text) if n in line]
    for i, line in hits[:12]:
      print(f'  {i}: {line[:120]}')
  print()
