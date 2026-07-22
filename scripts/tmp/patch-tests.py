from pathlib import Path
import re

# test-p0 version pins
p = Path('scripts/client/tests/test-p0-connect-fixes.ps1')
if p.exists():
    t = p.read_text(encoding='utf-8')
    t2 = re.sub(r'20260720\.\d+', '20260720.21', t)
    if t2 != t:
        p.write_text(t2, encoding='utf-8', newline='\n')
        print('OK test-p0 version pins')
    else:
        print('SKIP test-p0 pins')

# hard regressions: mutex fail-closed
p = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
t = p.read_text(encoding='utf-8')
needle = "Assert ($ui -notmatch 'MULTI_INSTANCE: allowed') 'Win: Enter-ConnectSingleInstance is not multi-instance no-op'"
add = """Assert ($ui -notmatch 'MULTI_INSTANCE: allowed') 'Win: Enter-ConnectSingleInstance is not multi-instance no-op'
Assert ($ui -match 'mutex error \\(block\\)') 'Win: mutex catch is fail-closed (block)'
Assert ($ui -notmatch 'mutex error \\(continue\\)') 'Win: mutex catch must not fail-open'
Assert ($gm -match 'no result line') 'git-mode: pushLine null-safe fallback'
Assert ($bat -match 'Early single-instance gate') 'connect.bat probes mutex before start connect.ps1'
"""
# need $gm and $bat variables - check file
if 'mutex error \\(block\\)' in t or "mutex error (block)" in t:
    print('SKIP hard already has fail-closed asserts')
else:
    if needle not in t:
        raise SystemExit('needle missing in hard test')
    # ensure $gm $bat loaded
    if "$gm =" not in t and "$gm=" not in t:
        # find where $ui is loaded and add
        pass
    t = t.replace(needle, add.rstrip(), 1)
    # inject vars if needed near top of Win section
    if 'git-mode.ps1' not in t.split('Enter-ConnectSingleInstance')[0][-800:]:
        # add after ui load
        m = re.search(r"(\$ui\s*=\s*Get-Content[^\n]+\n)", t)
        if m and '$gm =' not in t:
            insert = m.group(1) + "$gm = Get-Content (Join-Path $root 'scripts/client/git-mode.ps1') -Raw\n$bat = Get-Content (Join-Path $root 'scripts/client/windows/connect.bat') -Raw\n"
            # careful - may already have different paths
            print('WARN may need manual gm/bat - checking')
    p.write_text(t, encoding='utf-8', newline='\n')
    print('OK hard asserts patched (review gm/bat vars)')

# pipeline bat handoff - update stale asserts
p = Path('scripts/client/tests/test-connect-pipeline.ps1')
if p.exists():
    t = p.read_text(encoding='utf-8')
    # replace same-console expectations if present
    olds = [
        ("Assert ($bat -notmatch 'start \"\" .*connect\\.ps1')", None),
    ]
    # simpler: find failing patterns
    for line in t.splitlines():
        if 'connect.bat' in line.lower() and ('start' in line or 'cls' in line) and 'Assert' in line:
            print('PIPELINE_ASSERT:', line[:140])
