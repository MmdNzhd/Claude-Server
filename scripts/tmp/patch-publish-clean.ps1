$path = (Resolve-Path (Join-Path $PSScriptRoot '..\..\publish\publish.ps1')).Path
$lines = [System.Collections.Generic.List[string]]@(Get-Content $path)

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[switch\]\$SkipVersionBump') {
        if ($lines[$i+1] -notmatch 'SkipServerDeploy') {
            $lines[$i] = '    [switch]$SkipVersionBump,'
            $lines.Insert($i+1, '    [switch]$SkipServerDeploy,')
            $lines.Insert($i+2, '    [switch]$SmartOnly,')
            $lines.Insert($i+3, '    [switch]$SepidzOnly')
        }
        break
    }
}

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "ErrorActionPreference = 'Stop'") {
        if ($lines[$i+1] -notmatch 'SmartOnly') {
            $lines.Insert($i+1, "if (`$SmartOnly -and `$SepidzOnly) { Write-Err 'Use only one of -SmartOnly or -SepidzOnly' }")
        }
        break
    }
}

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'Publishing \$PackageName \(client only\)') {
        $lines.Insert($i, 'if (-not $SepidzOnly) {')
        break
    }
}

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'Write-Ok "\$PackageName\.zip"') {
        $deploy = @(
            '',
            '    if (-not $SkipServerDeploy) {',
            '        Write-Host ""',
            '        Write-Host "Deploying Smart server bundle..." -ForegroundColor White',
            '        Write-Host ""',
            '        & (Join-Path $PSScriptRoot ''deploy-smart-bundle.ps1'') -ProjectRoot $ProjectRoot -SmartClientRoot $OutDir',
            '        if ($LASTEXITCODE -ne 0) { Write-Err "Smart server deploy failed (use -SkipServerDeploy to skip)" }',
            '    }',
            '}',
            '',
            'if (-not $SmartOnly) {'
        )
        for ($j = $deploy.Count - 1; $j -ge 0; $j--) { $lines.Insert($i + 1, $deploy[$j]) }
        break
    }
}

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'Write-Ok "\$SepidName\.zip"') {
        $deploy = @(
            '',
            '    if (-not $SkipServerDeploy) {',
            '        Write-Host ""',
            '        Write-Host "Deploying Sepidz server bundle..." -ForegroundColor White',
            '        Write-Host ""',
            '        & (Join-Path $PSScriptRoot ''deploy-client-bundles.ps1'') `',
            '            -ProjectRoot $ProjectRoot `',
            '            -SmartClientRoot $OutDir `',
            '            -SepidClientRoot (Join-Path $SepidDir ''claude-code'') `',
            '            -DeploySmart:$false `',
            '            -DeploySepidz:$true',
            '        if ($LASTEXITCODE -ne 0) { Write-Err "Sepidz server deploy failed (use -SkipServerDeploy to skip)" }',
            '    }',
            '}'
        )
        for ($j = $deploy.Count - 1; $j -ge 0; $j--) { $lines.Insert($i + 1, $deploy[$j]) }
        break
    }
}

$text = ($lines -join "`r`n")
$doneOld = "Write-Host `"`"`r`nWrite-Host `"Done.`" -ForegroundColor Green`r`nWrite-Host `"  Main (Smart IP)  : Desktop\claude-publish\`$PackageName`" -ForegroundColor Green`r`nWrite-Host `"  Sepidz (IP patch): Desktop\claude-publish\`$SepidName`" -ForegroundColor Green`r`nif (-not `$NoZip) {`r`n    Write-Host `"  Main ZIP         : Desktop\claude-publish\`$PackageName.zip`" -ForegroundColor Green`r`n    Write-Host `"  Sepidz ZIP       : Desktop\claude-publish\`$SepidName.zip`" -ForegroundColor Green`r`n}`r`nWrite-Host `"`""
$doneNew = @'
Write-Host ""
Write-Host "Done." -ForegroundColor Green
if (-not $SepidzOnly) {
    Write-Host "  Main (Smart IP)  : Desktop\claude-publish\$PackageName" -ForegroundColor Green
    if (-not $NoZip) { Write-Host "  Main ZIP         : Desktop\claude-publish\$PackageName.zip" -ForegroundColor Green }
}
if (-not $SmartOnly) {
    Write-Host "  Sepidz (IP patch): Desktop\claude-publish\$SepidName" -ForegroundColor Green
    if (-not $NoZip) { Write-Host "  Sepidz ZIP       : Desktop\claude-publish\$SepidName.zip" -ForegroundColor Green }
}
Write-Host ""
'@
if ($text -notmatch 'if \(-not \$SepidzOnly\) \{[\r\n]+    Write-Host "  Main') {
    $text = $text -replace '(?s)(Write-Host ""\r?\nWrite-Host "Done\." -ForegroundColor Green\r?\nWrite-Host "  Main \(Smart IP\).*?Write-Host ""\r?\n)', $doneNew
}
Set-Content $path -Value $text -Encoding UTF8
Write-Host "patched publish.ps1"
