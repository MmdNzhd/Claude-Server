from pathlib import Path
path = Path.cwd() / "publish" / "publish.ps1"
c = path.read_text(encoding="utf-8-sig")
old = "    }\n}\n\nif (-not $SmartOnly) {\nWrite-Host \"\"\nWrite-Host \"Building Sepidz package"
new = "    }\n}\n\n}\n\nif (-not $SmartOnly) {\nWrite-Host \"\"\nWrite-Host \"Building Sepidz package"
if old not in c:
    raise SystemExit('pattern not found')
path.write_text(c.replace(old, new, 1), encoding="utf-8")
print('added SepidzOnly close')
