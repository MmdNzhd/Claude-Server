from pathlib import Path
import sys
p = Path(sys.argv[1]) / 'publish/build-windows-exe.ps1'
b = p.read_text(encoding='utf-8')
if 'CLAUDE_CONNECT_SETUP_NO_LAUNCH' in b:
    print('already patched')
    sys.exit(0)
idx = b.find("$alive = @(Get-CimInstance Win32_Process")
if idx < 0:
    raise SystemExit('alive not found')
insert = """    if ($env:CLAUDE_CONNECT_SETUP_NO_LAUNCH -eq '1') {
        Log 'setup files-only (NO_LAUNCH=1) - skip connect.bat'
        exit 0
    }

"""
p.write_text(b[:idx] + insert + b[idx:], encoding='utf-8', newline='\n')
print('patched OK')
