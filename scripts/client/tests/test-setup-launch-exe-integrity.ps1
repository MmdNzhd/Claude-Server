#Requires -Version 5.1
# EXE setup-launch: never fast_path on txt-only match; never stamp version lies.
# Run: powershell -NoProfile -File scripts\client\tests\test-setup-launch-exe-integrity.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here '_paths.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "PASS $msg" -ForegroundColor Green }
    else { Write-Host "FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $here '..\..\..'))
$bodyPath = Join-Path $repoRoot 'publish\_setup-launch-body.ps1'
Assert (Test-Path -LiteralPath $bodyPath) "setup-launch body exists at $bodyPath"
if (-not (Test-Path -LiteralPath $bodyPath)) { exit 1 }

$raw = Get-Content -LiteralPath $bodyPath -Raw
$cut = $raw.IndexOf("`r`ntry {")
if ($cut -lt 0) { $cut = $raw.IndexOf("`ntry {") }
Assert ($cut -gt 0) 'setup-launch body has main try block'
$tmpF = Join-Path $env:TEMP ('cc-setup-funcs-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
[IO.File]::WriteAllText($tmpF, $raw.Substring(0, $cut), [Text.UTF8Encoding]::new($false))
. $tmpF

Assert ($raw -match 'prefer_disk_newer') 'body prefers newer healthy disk VerDir over stale SFX package'
Assert ($raw -match 'Get-ConnectPs1EmbeddedVersionLocal') 'body parses connect.ps1 ConnectVersion'
Assert ($raw -match 'Never lie') 'body refuses Set-SrcVersionStamp lie'
Assert ($raw -match 'STALE-SHADOW') 'EXE Test-VersionSrcComplete rejects STALE-SHADOW ui/diagnostic'

$root = Join-Path $env:TEMP ('cc-exe-integrity-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$src = Join-Path $root 'src'
New-Item -ItemType Directory -Force -Path $src | Out-Null
@('connect.bat', 'connect-boot.ps1', 'connect-update.ps1', 'editor-launch.ps1', 'connect-ui.ps1', 'connect-env-repair.ps1') | ForEach-Object {
    Set-Content -LiteralPath (Join-Path $src $_) -Value '#stub' -Encoding ASCII
}
Set-Content -LiteralPath (Join-Path $src 'connect.ps1') -Value "`$script:ConnectVersion = '20260803.1'" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $src 'connect-version.txt') -Value '20260802.4' -Encoding ASCII -NoNewline

Assert (-not (Test-VersionSrcComplete -SrcDir $src -Version '20260802.4')) `
    'EXE fast_path blocked when txt=package but ps1 disagrees'

Set-SrcVersionStamp -SrcDir $src -Version '20260802.4'
Assert (((Get-Content (Join-Path $src 'connect-version.txt') -Raw).Trim()) -eq '20260803.1') `
    'stamp stays honest to connect.ps1 (no folder/package lie)'

Set-Content -LiteralPath (Join-Path $src 'connect.ps1') -Value "`$script:ConnectVersion = '20260803.8'" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $src 'connect-version.txt') -Value '20260803.8' -Encoding ASCII -NoNewline
Assert (Test-VersionSrcComplete -SrcDir $src -Version '20260803.8') 'healthy matching tree allows fast_path'
Set-Content -LiteralPath (Join-Path $src 'connect-diagnostic.ps1') -Value "# STALE-SHADOW REPLACED`n# stub" -Encoding ASCII
Assert (-not (Test-VersionSrcComplete -SrcDir $src -Version '20260803.8')) 'EXE fast_path blocked when diagnostic is STALE-SHADOW'

Remove-Item -LiteralPath $root, $tmpF -Recurse -Force -ErrorAction SilentlyContinue
if ($fail -gt 0) { Write-Host "FAILED $fail"; exit 1 }
Write-Host 'ALL PASS'
exit 0
