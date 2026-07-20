from pathlib import Path
path = Path.cwd() / "publish" / "publish.ps1"
content = path.read_text(encoding="utf-8-sig")
# Remove duplicate closing brace after Smart section
bad = "    }\n}\n\n}\n\nif (-not $SmartOnly) {"
good = "    }\n}\n\nif (-not $SmartOnly) {"
if bad not in content:
    raise SystemExit("duplicate brace pattern not found")
content = content.replace(bad, good, 1)
# Close SmartOnly block before Done
bad2 = "    }\n}\n\nWrite-Host \"\"\nWrite-Host \"Done.\""
good2 = "    }\n}\n}\n\nWrite-Host \"\"\nWrite-Host \"Done.\""
if bad2 not in content:
    raise SystemExit("SmartOnly close pattern not found")
content = content.replace(bad2, good2, 1)
path.write_text(content, encoding="utf-8")
print("Fixed braces")
