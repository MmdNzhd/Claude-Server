from pathlib import Path
p = Path('scripts/client/tests/run-all.ps1')
c = p.read_text(encoding='utf-8')
needle = "    @{ Name = 'connect-update-fail-exit'; Script = 'test-connect-update-fail-exit.ps1' }\n)"
insert = """    @{ Name = 'connect-update-fail-exit'; Script = 'test-connect-update-fail-exit.ps1' }
    @{ Name = 'session-log-contracts'; Script = 'test-session-log-contracts.ps1' }
    @{ Name = 'hard-multi-agent-regressions'; Script = 'test-hard-multi-agent-regressions.ps1' }
)"""
if 'hard-multi-agent-regressions' in c:
    print('already wired')
else:
    if needle not in c:
        raise SystemExit('needle not found')
    p.write_text(c.replace(needle, insert, 1), encoding='utf-8', newline='\n')
    print('OK run-all')
