from pathlib import Path
repo = Path.cwd()
path = repo / "publish" / "publish.ps1"
content = path.read_text(encoding="utf-8-sig")
old = """
if (-not $SmartOnly) {
}

Write-Host ""
Write-Host "Building Sepidz package (client only, IP patched)..." -ForegroundColor White
"""
new = """
}

if (-not $SmartOnly) {
Write-Host ""
Write-Host "Building Sepidz package (client only, IP patched)..." -ForegroundColor White
"""
if old not in content:
    raise SystemExit("empty SmartOnly block not found")
content = content.replace(old, new, 1)
old_deploy = """        & (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
            -ProjectRoot $ProjectRoot `
            -SmartClientRoot $OutDir `
            -SepidClientRoot (Join-Path $SepidDir 'claude-code') `
            -DeploySmart:$false `
            -DeploySepidz:$true"""
new_deploy = """        & (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
            -ProjectRoot $ProjectRoot `
            -SepidClientRoot (Join-Path $SepidDir 'claude-code') `
            -DeploySmart:$false `
            -DeploySepidz:$true"""
content = content.replace(old_deploy, new_deploy, 1)
old_done = """Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Main (Smart IP)  : Desktop\\claude-publish\\$PackageName" -ForegroundColor Green
Write-Host "  Sepidz (IP patch): Desktop\\claude-publish\\$SepidName" -ForegroundColor Green
if (-not $NoZip) {
    Write-Host "  Main ZIP         : Desktop\\claude-publish\\$PackageName.zip" -ForegroundColor Green
    Write-Host "  Sepidz ZIP       : Desktop\\claude-publish\\$SepidName.zip" -ForegroundColor Green
}"""
new_done = """Write-Host ""
Write-Host "Done." -ForegroundColor Green
if (-not $SepidzOnly) {
    Write-Host "  Main (Smart IP)  : Desktop\\claude-publish\\$PackageName" -ForegroundColor Green
    if (-not $NoZip) { Write-Host "  Main ZIP         : Desktop\\claude-publish\\$PackageName.zip" -ForegroundColor Green }
}
if (-not $SmartOnly) {
    Write-Host "  Sepidz (IP patch): Desktop\\claude-publish\\$SepidName" -ForegroundColor Green
    if (-not $NoZip) { Write-Host "  Sepidz ZIP       : Desktop\\claude-publish\\$SepidName.zip" -ForegroundColor Green }
}"""
content = content.replace(old_done, new_done, 1)
content = content.replace("    }\n}\n}\n\nWrite-Host \"\"\nWrite-Host \"Done.\"", "    }\n}\n\nWrite-Host \"\"\nWrite-Host \"Done.\"", 1)
path.write_text(content, encoding="utf-8")
print("Fixed", path)
