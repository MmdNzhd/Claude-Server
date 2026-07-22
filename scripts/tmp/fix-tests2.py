from pathlib import Path
import re

# designer PubB
p = Path('scripts/client/users/designer/connect.ps1')
t = p.read_text(encoding='utf-8')
old = "$PubB    = ($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1).Trim()"
new = "$PubB    = ([string](($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1) + '')).Trim()"
if old in t:
    p.write_text(t.replace(old, new, 1), encoding='utf-8', newline='\n')
    print('OK designer PubB')
else:
    print('FAIL designer')

# hard test - ensure $gm $bat exist
p = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
t = p.read_text(encoding='utf-8')
if '$gm =' not in t and '$gm=' not in t:
    # insert after $ui =
    m = re.search(r"(\$ui\s*=\s*[^\n]+\n)", t)
    if not m:
        raise SystemExit('no $ui=')
    insert = m.group(1) + (
        "$gm = Get-Content (Join-Path $ClientRoot 'git-mode.ps1') -Raw -ErrorAction SilentlyContinue\n"
        "if (-not $gm) { $gm = Get-Content (Join-Path $RepoRoot 'scripts/client/git-mode.ps1') -Raw }\n"
        "$bat = Get-Content (Join-Path $ClientRoot 'windows/connect.bat') -Raw -ErrorAction SilentlyContinue\n"
        "if (-not $bat) { $bat = Get-Content (Join-Path $RepoRoot 'scripts/client/windows/connect.bat') -Raw }\n"
    )
    # Check variable names used in file
    print('VARS sample:', [x for x in re.findall(r'\$[A-Za-z]+Root|\$root|\$ClientRoot|\$RepoRoot', t)[:20]])
    # find how $ui is assigned
    for line in t.splitlines():
        if '$ui' in line and ('Get-Content' in line or '=' in line) and 'Assert' not in line:
            print('UI_LINE:', line[:160])

# Fix pipeline asserts
p = Path('scripts/client/tests/test-connect-pipeline.ps1')
t = p.read_text(encoding='utf-8')
t2 = t.replace(
    "Assert ($connectBat -notmatch 'start \"\" /D \"%HERE%\" powershell.*connect\\.ps1') 'connect.bat handoffs connect.ps1 in same console (no start s",
    "Assert ($connectBat -match 'start \"\" /D \"%HERE%\" powershell.*connect\\.ps1') 'connect.bat async handoffs connect.ps1 via start ("
)
# might be truncated differently - do line-based
lines = t.splitlines(True)
out = []
for line in lines:
    if "handoffs connect.ps1 in same console" in line or ("notmatch" in line and 'connect.ps1' in line and 'start' in line and 'connectBat' in line):
        out.append("Assert ($connectBat -match 'start \"\" /D \"%HERE%\" powershell.*connect\\.ps1') 'connect.bat async handoff starts connect.ps1'\n")
        print('REPLACED same-console assert')
    elif "clears screen before connect UI" in line or ("connectBat" in line and "\\\\bcls\\\\b" in line):
        out.append("Assert ($connectBat -match 'Early single-instance gate') 'connect.bat probes mutex before spawning connect.ps1'\n")
        print('REPLACED cls assert')
    else:
        out.append(line)
p.write_text(''.join(out), encoding='utf-8', newline='\n')
print('OK pipeline patched')
