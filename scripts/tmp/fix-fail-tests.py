from pathlib import Path

sp = Path('scripts/client/tests/test-session-log-contracts.ps1')
sc = sp.read_text(encoding='utf-8')
print('MULTI in session', 'MULTI_INSTANCE' in sc)
print('FAIL EXIT in session', 'FAIL EXIT' in sc)
print('--- tail ---')
print('\n'.join(sc.splitlines()[-50:]))

p = Path('scripts/client/tests/test-connect-pipeline.ps1')
c = p.read_text(encoding='utf-8')
# Remove dead code after exit 1 (unreachable asserts we added)
marker = "Write-Host \"$fail test(s) failed.\" -ForegroundColor Red; exit 1\n"
idx = c.find(marker)
if idx < 0:
    raise SystemExit('exit marker not found')
# keep everything through exit 1, drop unreachable after
end = idx + len(marker)
tail = c[end:].lstrip('\n')
print('--- unreachable head ---')
print(repr(tail[:200]))
# If unreachable starts with our session asserts / blank / comments, strip until EOF of those
# Safer: if after exit there's content starting with blank+# Session ID, delete from there
if '# Session ID + silent update' in c[end:] or "Assert ($ui -match 'MULTI_INSTANCE" in c[end:]:
    c2 = c[:end]
    if not c2.endswith('\n'):
        c2 += '\n'
    p.write_text(c2, encoding='utf-8', newline='\n')
    print('OK removed unreachable pipeline asserts')
else:
    print('no unreachable block to remove')

# Add to session-log contracts before final pass message
adds = """
Assert ($ui -match 'FAIL EXIT reason=') 'Wait-ConnectExit logs FAIL EXIT on non-zero code'
Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'
Assert ($winConnect -match 'FAIL NEED_ADMIN') 'connect.ps1 logs FAIL NEED_ADMIN'
Assert ($winConnect -match 'FAIL STEP name=') 'connect.ps1 logs FAIL STEP'
Assert ($winConnect -match 'FAIL ADMIN_UAC') 'connect.ps1 logs FAIL ADMIN_UAC'
$upd = Get-Content (Join-Path $root 'windows\\connect-update.ps1') -Raw -ErrorAction SilentlyContinue
if (-not $upd) { $upd = Get-Content (Join-Path $root 'connect-update.ps1') -Raw -ErrorAction SilentlyContinue }
Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'
"""

if 'FAIL EXIT reason=' in sc:
    print('session already has FAIL EXIT')
else:
    # insert before "All session-log contracts passed" or final exit
    for needle in [
        "Write-Host 'All session-log contracts passed'",
        'All session-log contracts passed',
        'exit 0',
    ]:
        if needle in sc:
            sc = sc.replace(needle, adds + '\n' + needle, 1)
            sp.write_text(sc, encoding='utf-8', newline='\n')
            print('OK inserted before', needle)
            break
    else:
        raise SystemExit('no insert point in session contracts')
print('DONE')
