$ErrorActionPreference = 'Stop'
$repo = Get-Location
$fail = 0
function Assert([bool]$cond, [string]$msg) {
    if (-not $cond) { Write-Host "FAIL: $msg" -ForegroundColor Red; $script:fail++ }
    else { Write-Host "OK  : $msg" -ForegroundColor Green }
}

$scripts = @(
    'publish\publish.ps1',
    'publish\deploy-client-bundles.ps1',
    'publish\deploy-smart-bundle.ps1',
    'publish\finish-smart-deploy.ps1',
    'publish\finish-sepidz-deploy.ps1',
    'publish\Get-DeployCredentials.ps1'
)
foreach ($rel in $scripts) {
    $p = Join-Path $repo $rel
    $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
    Assert (-not $e) "syntax $rel"
}

$files = @(
    'publish\publish.bat',
    'publish\publish-smart.bat',
    'publish\publish-sepidz.bat',
    'publish\finish-smart-deploy.bat',
    'publish\finish-sepidz-deploy.bat',
    'publish\sepidz-deploy.local.ps1.example',
    'scripts\server\commands\install-client-bundle.sh'
)
foreach ($rel in $files) {
    Assert (Test-Path (Join-Path $repo $rel)) "exists $rel"
}

$pub = Get-Content (Join-Path $repo 'publish\publish.ps1') -Raw
Assert ($pub -match '\[switch\]\$SkipServerDeploy') 'SkipServerDeploy param'
Assert ($pub -match '\[switch\]\$SmartOnly') 'SmartOnly param'
Assert ($pub -match '\[switch\]\$SepidzOnly') 'SepidzOnly param'
Assert ($pub -match 'deploy-smart-bundle\.ps1') 'Smart deploy hook'
Assert ($pub -match 'DeploySmart:\$false') 'Sepidz deploy DeploySmart false'
Assert ($pub -match '-SepidClientRoot \(Join-Path \$SepidDir') 'Sepidz deploy no SmartClientRoot'
Assert ($pub -match 'if \(-not \$SepidzOnly\)') 'Smart build guard'
Assert ($pub -match 'if \(-not \$SmartOnly\)') 'Sepidz build guard'

# Brace balance heuristic on publish.ps1
$open = ([regex]::Matches($pub, '\{')).Count
$close = ([regex]::Matches($pub, '\}')).Count
Assert ($open -eq $close) "publish.ps1 brace balance ($open open, $close close)"

$dep = Get-Content (Join-Path $repo 'publish\deploy-client-bundles.ps1') -Raw
Assert ($dep -match 'sepidz@192\.168\.250\.70') 'Sepidz SSH target'
Assert ($dep -match 'SmartClientRoot is required when -DeploySmart') 'Smart root validation'
Assert ($dep -match 'SepidClientRoot is required when -DeploySepidz') 'Sepid root validation'
Assert ($dep -match '\$labels = @\(\$targets') 'dynamic deploy success message'

$smartOnly = Get-Content (Join-Path $repo 'publish\deploy-smart-bundle.ps1') -Raw
Assert ($smartOnly -match 'DeploySepidz:\$false') 'deploy-smart DeploySepidz false'
Assert ($smartOnly -notmatch '-SepidClientRoot') 'deploy-smart no SepidClientRoot'

$finishSep = Get-Content (Join-Path $repo 'publish\finish-sepidz-deploy.ps1') -Raw
Assert ($finishSep -notmatch 'smartDir') 'finish-sepidz independent'
Assert ($finishSep -match 'publish-sepidz\.bat') 'finish-sepidz error mentions publish-sepidz'

$gi = Get-Content (Join-Path $repo '.gitignore') -Raw
Assert ($gi -match 'sepidz-deploy\.local\.ps1') 'gitignore credentials'

$credLocal = Join-Path $repo 'publish\sepidz-deploy.local.ps1'
if (Test-Path $credLocal) {
    $cred = Get-Content $credLocal -Raw
    Assert ($cred -match "SepidzSshUser\s*=\s*'sepidz'") 'local creds SSH user sepidz'
    Assert ($cred -match 'SepidzSudoPassword') 'local creds has sudo password'
    Write-Host 'OK  : sepidz-deploy.local.ps1 present on laptop' -ForegroundColor Green
} else {
    Write-Host 'WARN: publish\sepidz-deploy.local.ps1 missing (Sepidz auto-sudo may prompt)' -ForegroundColor Yellow
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'Static audit: ALL PASSED' -ForegroundColor Green; exit 0 }
Write-Host "Static audit: $fail FAILED" -ForegroundColor Red; exit 1
