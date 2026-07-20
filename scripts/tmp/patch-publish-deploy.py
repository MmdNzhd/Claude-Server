from pathlib import Path

path = Path.cwd() / "publish" / "publish.ps1"
content = path.read_text(encoding="utf-8-sig")

# 1) Extend param block
old_param = """param(
    [switch]$NoZip,
    [switch]$SkipVersionBump
)"""
new_param = """param(
    [switch]$NoZip,
    [switch]$SkipVersionBump,
    [switch]$SkipServerDeploy,
    [switch]$SmartOnly,
    [switch]$SepidzOnly
)"""
if old_param not in content:
    raise SystemExit("param block not found")
content = content.replace(old_param, new_param, 1)

# 2) Guard after ErrorActionPreference
old_eap = "$ErrorActionPreference = 'Stop'\n\n$ProjectRoot"
new_eap = "$ErrorActionPreference = 'Stop'\nif ($SmartOnly -and $SepidzOnly) { Write-Err 'Use only one of -SmartOnly or -SepidzOnly' }\n\n$ProjectRoot"
content = content.replace(old_eap, new_eap, 1)

# 3) Wrap Smart build section
old_smart = 'Write-Host ""\nWrite-Host "Publishing $PackageName (client only)"'
new_smart = 'Write-Host ""\nif (-not $SepidzOnly) {\nWrite-Host "Publishing $PackageName (client only)"'
content = content.replace(old_smart, new_smart, 1)

# 4) Smart deploy after main ZIP
old_zip = """    New-ClientZipFromDirectory -SourceDir $OutDir -ZipPath $ZipPath
    Write-Ok "$PackageName.zip"
}"""
new_zip = """    New-ClientZipFromDirectory -SourceDir $OutDir -ZipPath $ZipPath
    Write-Ok "$PackageName.zip"

    if (-not $SkipServerDeploy) {
        Write-Host ""
        Write-Host "Deploying Smart server bundle..." -ForegroundColor White
        Write-Host ""
        & (Join-Path $PSScriptRoot 'deploy-smart-bundle.ps1') -ProjectRoot $ProjectRoot -SmartClientRoot $OutDir
        if ($LASTEXITCODE -ne 0) { Write-Err "Smart server deploy failed (use -SkipServerDeploy to skip)" }
    }
}"""
content = content.replace(old_zip, new_zip, 1)

# 5) Close SepidzOnly block and wrap Sepidz in SmartOnly guard
old_sepid = """}

Write-Host ""
Write-Host "Building Sepidz package (client only, IP patched)..." """
new_sepid = """}

if (-not $SmartOnly) {
Write-Host ""
Write-Host "Building Sepidz package (client only, IP patched)..." """
content = content.replace(old_sepid, new_sepid, 1)

# 6) Sepidz deploy after Sepidz ZIP
old_sepid_zip = """    New-ClientZipFromDirectory -SourceDir $SepidDir -ZipPath $SepidZip
    Write-Ok "$SepidName.zip"
}

Write-Host ""
Write-Host "Done." """
new_sepid_zip = """    New-ClientZipFromDirectory -SourceDir $SepidDir -ZipPath $SepidZip
    Write-Ok "$SepidName.zip"

    if (-not $SkipServerDeploy) {
        Write-Host ""
        Write-Host "Deploying Sepidz server bundle..." -ForegroundColor White
        Write-Host ""
        & (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
            -ProjectRoot $ProjectRoot `
            -SepidClientRoot (Join-Path $SepidDir 'claude-code') `
            -DeploySmart:$false `
            -DeploySepidz:$true
        if ($LASTEXITCODE -ne 0) { Write-Err "Sepidz server deploy failed (use -SkipServerDeploy to skip)" }
    }
}

Write-Host ""
Write-Host "Done." """
content = content.replace(old_sepid_zip, new_sepid_zip, 1)

# 7) Close SmartOnly block before Done
old_done = """}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Main (Smart IP)  : Desktop\\claude-publish\\$PackageName" -ForegroundColor Green
Write-Host "  Sepidz (IP patch): Desktop\\claude-publish\\$SepidName" -ForegroundColor Green
if (-not $NoZip) {
    Write-Host "  Main ZIP         : Desktop\\claude-publish\\$PackageName.zip" -ForegroundColor Green
    Write-Host "  Sepidz ZIP       : Desktop\\claude-publish\\$SepidName.zip" -ForegroundColor Green
}"""
new_done = """}
}

Write-Host ""
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

path.write_text(content, encoding="utf-8")
print("Patched", path)
