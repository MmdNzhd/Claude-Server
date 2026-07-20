from pathlib import Path
p = Path('scripts/client/tests/test-connect-pipeline.ps1')
c = p.read_text(encoding='utf-8')
needle = "Assert ($ui -match 'Get-ConnectSessionId') 'connect-ui.ps1 Get-ConnectSessionId'"
add = """Assert ($ui -match 'Get-ConnectSessionId') 'connect-ui.ps1 Get-ConnectSessionId'
Assert ($ui -match 'MULTI_INSTANCE: allowed') 'connect-ui.ps1 allows unlimited concurrent instances'
Assert ($ui -notmatch 'Another Claude Connect is already running') 'connect-ui.ps1 must not block second instance'"""
if 'MULTI_INSTANCE: allowed' in c:
    print('already patched')
else:
    if needle not in c:
        raise SystemExit('needle not found')
    p.write_text(c.replace(needle, add, 1), encoding='utf-8', newline='\n')
    print('OK')
