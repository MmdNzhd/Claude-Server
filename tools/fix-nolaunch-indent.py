from pathlib import Path
p = Path('publish/build-windows-exe.ps1')
b = p.read_text(encoding='utf-8')
old = """        if ($env:CLAUDE_CONNECT_SETUP_NO_LAUNCH -eq '1') {
        Log 'setup files-only (NO_LAUNCH=1) - skip connect.bat'
        exit 0
    }

$alive = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {"""
new = """    if ($env:CLAUDE_CONNECT_SETUP_NO_LAUNCH -eq '1') {
        Log 'setup files-only (NO_LAUNCH=1) - skip connect.bat'
        exit 0
    }

    $alive = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {"""
if old not in b:
    i = b.find('CLAUDE_CONNECT_SETUP_NO_LAUNCH')
    print('OLD not found; context:')
    print(repr(b[i-80:i+250]))
    raise SystemExit(1)
p.write_text(b.replace(old, new, 1), encoding='utf-8', newline='\n')
print('fixed indentation')
# verify
b2 = p.read_text(encoding='utf-8')
i = b2.find('CLAUDE_CONNECT_SETUP_NO_LAUNCH')
print(repr(b2[i-40:i+200]))
