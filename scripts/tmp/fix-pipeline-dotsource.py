from pathlib import Path
p = Path('scripts/client/tests/test-connect-pipeline.ps1')
t = p.read_text(encoding='utf-8')
old = ". (Join-Path $PSScriptRoot 'test-session-log-contracts.ps1')"
new = """$sessionLogRc = 0
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-session-log-contracts.ps1')
if ($LASTEXITCODE -ne 0) { $sessionLogRc = [int]$LASTEXITCODE; $failed += 1; Write-Host 'FAIL session-log-contracts (see above)' -ForegroundColor Red }
"""
if old not in t:
    raise SystemExit('MISS dotsource')
t = t.replace(old, new, 1)
# ensure final exit uses $failed
if 'if ($failed' not in t and 'All tests passed' in t:
    t = t.replace(
        'Write-Host "`nAll tests passed." -ForegroundColor Green',
        'if ($failed -gt 0) { Write-Host ("`nFAILED {0} asserts" -f $failed) -ForegroundColor Red; exit 1 }\nWrite-Host "`nAll tests passed." -ForegroundColor Green',
        1)
p.write_text(t, encoding='utf-8', newline='\n')
print('pipeline fixed')

# contracts: when run standalone exit 1 is fine; ensure $failed var
c = Path('scripts/client/tests/test-session-log-contracts.ps1')
ct = c.read_text(encoding='utf-8')
if 'if ($failed -gt 0)' in ct:
    print('contracts exit ok')
