from pathlib import Path
path = Path.cwd() / "publish" / "publish.ps1"
c = path.read_text(encoding="utf-8-sig")
needle = 'Write-Host ""\nif (-not $SepidzOnly) {\nWrite-Host "Publishing'
insert = 'Write-Host ""\n$readmeSrc = Join-Path $PSScriptRoot "README.txt"\nif (-not $SepidzOnly) {\nWrite-Host "Publishing'
if needle not in c:
    raise SystemExit('needle not found')
c = c.replace(needle, insert, 1)
# Remove duplicate inside Smart block (keep validation)
old = 'Write-Step "Copying README.txt..."\n$readmeSrc = Join-Path $PSScriptRoot "README.txt"\nif (-not (Test-Path $readmeSrc))'
new = 'Write-Step "Copying README.txt..."\nif (-not (Test-Path $readmeSrc))'
if old not in c:
    raise SystemExit('inner readmeSrc not found')
c = c.replace(old, new, 1)
path.write_text(c, encoding="utf-8")
print('fixed readmeSrc for SepidzOnly')
