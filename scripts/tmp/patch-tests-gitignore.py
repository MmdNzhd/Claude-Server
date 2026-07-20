from pathlib import Path

gi = Path.cwd() / ".gitignore"
text = gi.read_text(encoding="utf-8")
if "sepidz-deploy.local.ps1" not in text:
    text = text.rstrip() + "\n\n# Sepidz deploy credentials (laptop only)\npublish/sepidz-deploy.local.ps1\n"
    gi.write_text(text + "\n", encoding="utf-8")
    print("updated .gitignore")

tests = Path.cwd() / "scripts/client/tests/test-publish.ps1"
t = tests.read_text(encoding="utf-8-sig")
extra = """
Assert ($pubRaw -match '\\[switch\\]\\$SmartOnly') 'publish.ps1 supports -SmartOnly'
Assert ($pubRaw -match '\\[switch\\]\\$SepidzOnly') 'publish.ps1 supports -SepidzOnly'
Assert ($pubRaw -match 'deploy-smart-bundle\\.ps1') 'publish.ps1 invokes deploy-smart-bundle.ps1 after Smart ZIP'
Assert (Test-Path (Join-Path $RepoRoot 'publish\\deploy-smart-bundle.ps1')) 'deploy-smart-bundle.ps1 exists'
Assert (Test-Path (Join-Path $RepoRoot 'publish\\publish-smart.bat')) 'publish-smart.bat exists'
Assert (Test-Path (Join-Path $RepoRoot 'publish\\publish-sepidz.bat')) 'publish-sepidz.bat exists'
"""
needle = "Assert ($pubRaw -match 'deploy-client-bundles\\.ps1') 'publish.ps1 invokes deploy-client-bundles.ps1'"
if extra.strip() not in t and needle in t:
    t = t.replace(needle, needle + extra, 1)
    tests.write_text(t, encoding="utf-8")
    print("updated test-publish.ps1")
