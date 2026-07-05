# test-publish.ps1 — publish output must be client-only; Smart/Sepidz differ only by IP
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

$SmartIp = '192.168.210.240'
$SepidIp = '192.168.250.70'
$Forbidden = @('21000', 'claude-connect-sepidz', 'claude-server-sepidz', 'users\sepidz', 'users/sepidz')

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function Test-PackageRoot {
    param([string]$Root, [string]$Label)
    if (-not (Test-Path $Root)) {
        Assert $false "$Label exists at $Root (run publish.ps1 first)"
        return
    }
    $serverDirs = @(Get-ChildItem -Path $Root -Recurse -Directory -Filter 'server' -ErrorAction SilentlyContinue)
    Assert ($serverDirs.Count -eq 0) "$Label has no server/ folder"
    foreach ($name in @('deploy-server-mount-fix.ps1', 'deploy-server-mount-fix.bat', 'deploy-mount-fix.sh', 'claude-automount.sh', 'claude-watchdog.sh')) {
        $hits = @(Get-ChildItem -Path $Root -Recurse -File -Filter $name -ErrorAction SilentlyContinue)
        Assert ($hits.Count -eq 0) "$Label has no $name"
    }
    $mountHits = @(Get-ChildItem -Path $Root -Recurse -File -Filter 'claude-mount.sh' -ErrorAction SilentlyContinue)
    $relMounts = @($mountHits | ForEach-Object { $_.FullName.Replace($Root, '').TrimStart('\', '/') })
    $allowedMounts = @(
        'mac\claude-mount.sh', 'mac/claude-mount.sh',
        'claude-code\mac\claude-mount.sh', 'claude-code/mac/claude-mount.sh'
    )
    $extraMounts = @($relMounts | Where-Object { $allowedMounts -notcontains $_ })
    Assert ($extraMounts.Count -eq 0) "$Label has claude-mount.sh only under mac/ (or claude-code/mac/)"
    $hasMount = (Test-Path (Join-Path $Root 'mac\claude-mount.sh')) -or
                (Test-Path (Join-Path $Root 'claude-code\mac\claude-mount.sh'))
    Assert $hasMount "$Label has mac/claude-mount.sh bootstrap copy"
    $hasWin = (Test-Path (Join-Path $Root 'windows\connect.ps1')) -or
              (Test-Path (Join-Path $Root 'claude-code\windows\connect.ps1'))
    Assert $hasWin "$Label includes windows\connect.ps1"
    $hasMac = (Test-Path (Join-Path $Root 'mac\connect.sh')) -or
              (Test-Path (Join-Path $Root 'claude-code\mac\connect.sh'))
    Assert $hasMac "$Label includes mac\connect.sh"
}

function Test-NoForbiddenStrings {
    param([string]$Root, [string]$Label)
    $textFiles = Get-ChildItem -Path $Root -Recurse -File -Include *.ps1,*.sh,*.bat,*.md,*.txt -ErrorAction SilentlyContinue
    foreach ($f in $textFiles) {
        $raw = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        foreach ($bad in $Forbidden) {
            if ($raw -match [regex]::Escape($bad)) {
                Assert $false "$Label $($f.FullName) contains forbidden '$bad'"
            }
        }
    }
    Assert $true "$Label has no sepidz-fork strings (21000, claude-connect-sepidz, ...)"
}

function Test-NoUtf8Bom {
    param([string]$Path, [string]$Label)
    $b = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    Assert (-not $hasBom) "$Label has no UTF-8 BOM ($([IO.Path]::GetFileName($Path)))"
}

function Test-BinaryIdenticalExceptIp {
    param(
        [string]$MainRoot,
        [string]$SepidRoot,
        [string[]]$PatchRel
    )
    Get-ChildItem $MainRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($MainRoot.Length).TrimStart('\')
        if ($rel -match '(^|\\)README(\.|$)') { return }
        $sepidPath = Join-Path $SepidRoot $rel
        if (-not (Test-Path $sepidPath)) {
            Assert $false "sepid missing mirrored file: $rel"
            return
        }
        if ($PatchRel -contains $rel) { return }
        $a = [System.IO.File]::ReadAllBytes($_.FullName)
        $b = [System.IO.File]::ReadAllBytes($sepidPath)
        Assert (($a.Length -eq $b.Length) -and ([Convert]::ToBase64String($a) -eq [Convert]::ToBase64String($b))) "binary identical: $rel"
    }
}

function Test-SingleIpLiteral {
    param([string]$Path, [string]$ExpectedIp, [string]$Label)
    $raw = Get-Content $Path -Raw
    $count = ([regex]::Matches($raw, [regex]::Escape($ExpectedIp))).Count
    Assert ($count -eq 1) "$Label has exactly 1 IP literal (got $count)"
}

function Test-SmartSepidzDiff {
    param(
        [string]$SmartPath,
        [string]$SepidPath,
        [string]$Name
    )
    if (-not ((Test-Path $SmartPath) -and (Test-Path $SepidPath))) {
        Assert $false "$Name diff: both files exist"
        return
    }
    $smart = (Get-Content $SmartPath -Raw) -replace [regex]::Escape($SmartIp), '__IP__'
    $sepid = (Get-Content $SepidPath -Raw) -replace [regex]::Escape($SepidIp), '__IP__'
    Assert ($smart -eq $sepid) "$Name differs only by SERVER_IP"
    $sepidRaw = Get-Content $SepidPath -Raw
    Assert ($sepidRaw -match [regex]::Escape($SepidIp)) "$Name Sepidz copy has Sepidz IP"
    Assert ($sepidRaw -notmatch [regex]::Escape($SmartIp)) "$Name Sepidz copy has no Smart IP"
}

Write-Host ''
Write-Host '=== Publish deep audit ===' -ForegroundColor Cyan
Write-Host ''

$publishPs1 = Get-Content (Join-Path $script:RepoRoot 'publish\publish.ps1') -Raw
Assert ($publishPs1 -notmatch '\$ServerScripts') 'publish.ps1 has no ServerScripts block'
Assert ($publishPs1 -notmatch '\$DeployScripts') 'publish.ps1 has no DeployScripts in ZIP'
Assert ($publishPs1 -match 'Assert-ClientPackage') 'publish.ps1 validates client-only output'
Assert ($publishPs1 -notmatch 'users\\sepidz') 'publish.ps1 uses single codebase (no sepidz fork)'

$pubBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$main = Get-ChildItem (Join-Path $pubBase 'claude-code-client-*') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
$sepid = Get-ChildItem (Join-Path $pubBase 'claude-code-sepidz-*') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1

if ($main) {
    Test-PackageRoot -Root $main.FullName -Label 'main publish folder'
    Test-NoForbiddenStrings -Root $main.FullName -Label 'main'
    $mainFiles = @(Get-ChildItem $main.FullName -Recurse -File | ForEach-Object { $_.FullName.Replace($main.FullName, '').TrimStart('\') })
    Assert ($mainFiles -contains 'README.txt') 'main has README.txt'
    Assert ($mainFiles -contains 'windows\connect.ps1') 'main has windows\connect.ps1'
    Assert ($mainFiles -contains 'mac\connect.sh') 'main has mac\connect.sh'
    Assert ($mainFiles -contains 'windows\connect-ui.ps1') 'main has connect-ui.ps1'
    Assert ($mainFiles -contains 'mac\connect-ui.sh') 'main has connect-ui.sh'
    Assert ($mainFiles -contains 'mac\editor-launch.sh') 'main has editor-launch.sh'
    Assert ($mainFiles -contains 'mac\claude-mount.sh') 'main has mac/claude-mount.sh bootstrap copy'
    Assert ($mainFiles -contains 'windows\connect-version.txt') 'main has connect-version.txt'
    Assert ($mainFiles.Count -eq 14) "main has exactly 14 client files (got $($mainFiles.Count))"
    $smartPs1 = Get-Content (Join-Path $main.FullName 'windows\connect.ps1') -Raw
    Assert ($smartPs1 -match 'claude-server') 'main connect.ps1 alias claude-server'
    Assert ($smartPs1 -match 'claude-connect') 'main connect.ps1 cfg claude-connect'
    Assert ($smartPs1 -match '20000 \+') 'main connect.ps1 port base 20000'
    Test-SingleIpLiteral -Path (Join-Path $main.FullName 'windows\connect.ps1') -ExpectedIp $SmartIp -Label 'main connect.ps1'
    Test-NoUtf8Bom -Path (Join-Path $main.FullName 'windows\connect.ps1') -Label 'main'
    $bat = Get-Content (Join-Path $main.FullName 'windows\connect.bat') -Raw
    Assert ($bat -match 'connect-version\.txt') 'connect.bat requires connect-version.txt'
} else {
    Assert $false 'main publish folder found (run publish.ps1)'
}

if ($sepid) {
    Test-PackageRoot -Root $sepid.FullName -Label 'sepidz publish folder'
    Test-NoForbiddenStrings -Root $sepid.FullName -Label 'sepidz'
    $cc = Join-Path $sepid.FullName 'claude-code'
    $des = Join-Path $sepid.FullName 'designer'
    Assert (Test-Path $cc) 'sepidz has claude-code/'
    Assert (Test-Path $des) 'sepidz has designer/'
    Assert (-not (Test-Path (Join-Path $cc 'server'))) 'sepidz claude-code has no server/'
    Assert (-not (Test-Path (Join-Path $des 'server'))) 'sepidz designer has no server/'
    if ($main) {
        Test-SmartSepidzDiff `
            -SmartPath (Join-Path $main.FullName 'windows\connect.ps1') `
            -SepidPath (Join-Path $cc 'windows\connect.ps1') `
            -Name 'connect.ps1'
        Test-SmartSepidzDiff `
            -SmartPath (Join-Path $main.FullName 'mac\connect.sh') `
            -SepidPath (Join-Path $cc 'mac\connect.sh') `
            -Name 'connect.sh'
        Test-NoUtf8Bom -Path (Join-Path $cc 'windows\connect.ps1') -Label 'sepidz'
        Test-NoUtf8Bom -Path (Join-Path $cc 'mac\connect.sh') -Label 'sepidz'
        Test-SingleIpLiteral -Path (Join-Path $cc 'windows\connect.ps1') -ExpectedIp $SepidIp -Label 'sepidz connect.ps1'
        Test-SingleIpLiteral -Path (Join-Path $cc 'mac\connect.sh') -ExpectedIp $SepidIp -Label 'sepidz connect.sh'
        Test-BinaryIdenticalExceptIp -MainRoot $main.FullName -SepidRoot $cc -PatchRel @('windows\connect.ps1', 'mac\connect.sh')
        $mainPs1 = Join-Path $main.FullName 'windows\connect.ps1'
        $sepidPs1 = Join-Path $cc 'windows\connect.ps1'
        $mainBytes = [IO.File]::ReadAllBytes($mainPs1)
        $sepidBytes = [IO.File]::ReadAllBytes($sepidPs1)
        $expectedDelta = $SepidIp.Length - $SmartIp.Length
        Assert ($sepidBytes.Length -eq ($mainBytes.Length + $expectedDelta)) "connect.ps1 size delta = IP length diff ($expectedDelta bytes)"
    }
    $desPs1 = Get-Content (Join-Path $des 'windows\connect.ps1') -Raw
    Assert ($desPs1 -match [regex]::Escape($SepidIp)) 'designer Sepidz IP patched'
} else {
    Assert $false 'sepidz publish folder found (run publish.ps1)'
}

$gitModePs1 = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
Assert ($gitModePs1 -match 'scripts.*server') 'Resolve-ServerScriptDir finds repo scripts/server'
$gitModeSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
Assert ($gitModeSh -match 'scripts/server') 'resolve_server_script_dir finds repo scripts/server'
$designerSh = Get-Content (Get-ClientFile 'users\designer\connect.sh') -Raw
Assert ($designerSh -match 'resolve_server_script_dir') 'designer connect.sh uses shared resolve (not broken ../../server)'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All publish deep tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
