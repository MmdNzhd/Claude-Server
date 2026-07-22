import re
from pathlib import Path
files=[
'scripts/client/windows/connect.ps1',
'scripts/client/connect-ui.ps1',
'scripts/client/editor-launch.ps1',
'scripts/client/git-mode.ps1',
'scripts/client/windows/windows-mcp-laptop.ps1',
'scripts/client/windows/connect-diagnostic.ps1',
]
for f in files:
 p=Path(f)
 if not p.exists():
  print('MISSING', f); continue
 text=p.read_text(encoding='utf-8', errors='replace')
 lines=text.splitlines()
 print('%s | lines=%d WCL=%d WH=%d SC=%d catchEmpty=%d catchBlocks=%d' % (
  f, len(lines), text.count('Write-ConnectLog'), text.count('Write-Host'),
  text.count('SilentlyContinue'), len(re.findall(r'catch\s*\{\s*\}', text)),
  len(re.findall(r'catch\s*\{', text))))
