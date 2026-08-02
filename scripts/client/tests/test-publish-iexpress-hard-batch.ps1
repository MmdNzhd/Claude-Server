#Requires -Version 5.1
# test-publish-iexpress-hard-batch.ps1 - HARD batch gate for IExpress SFX + versioned install +
# publish client-only / Sepidz IP invariants (14 Assert calls). Does NOT modify run-all.ps1.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== publish / IExpress hard batch (2026-07-27) ===' -ForegroundColor Cyan
Write-Host ''

$build = Get-Content (Join-Path $RepoRoot 'publish\build-windows-exe.ps1') -Raw
$launch = Get-Content (Join-Path $RepoRoot 'publish\_setup-launch-body.ps1') -Raw
$worker = Get-Content (Join-Path $RepoRoot 'publish\_setup-worker-body.ps1') -Raw
$publish = Get-Content (Join-Path $RepoRoot 'publish\publish.ps1') -Raw

# 1) AppLaunched=wscript hidden VBS (not raw powershell on SED line)
Assert ($build -match "AppLaunched=wscript\.exe //B //Nologo setup-run-hidden\.vbs") `
    'AppLaunched is wscript //B //Nologo setup-run-hidden.vbs'

# 2) NOT raw powershell Bypass+Hidden on AppLaunched
Assert (-not ($build -match '(?i)AppLaunched=powershell\.exe|AppendLine\(''AppLaunched=powershell')) `
    'AppLaunched is not powershell Bypass+Hidden (Defender SFX heuristic)'

# 3) setup-claude-connect.cmd still staged (manual recovery only; VBS must not call it)
Assert ($build -match 'setup-claude-connect\.cmd') `
    'IExpress stage ships setup-claude-connect.cmd (recovery only)'

# 4) VBS launches powershell directly with style 0 (no cmd.exe flash)
Assert ($build -match 'sh\.Run ps, 0, True') `
    'setup-run-hidden.vbs uses sh.Run style 0 on powershell (no console flash)'
Assert ($build -match 'setup-launch\.ps1') `
    'setup-run-hidden.vbs targets setup-launch.ps1'
Assert ($build -notmatch 'cmd\.exe /c') `
    'setup-run-hidden.vbs must not spawn cmd.exe /c (visible flash)'

# 5) Versioned tree Claude-Connect\{ver}\src
Assert ($launch -match 'Join-Path \$verDir ''src''') `
    'setup-launch resolves Claude-Connect\{ver}\src versioned layout'

# 6) Write-ConnectInstantLauncher vbs + cmd trampoline
Assert ($launch -match 'Write-ConnectInstantLauncher' -and $launch -match 'Claude-Connect\.vbs' -and $launch -match 'Claude-Connect\.cmd') `
    'Write-ConnectInstantLauncher writes Claude-Connect.vbs and .cmd trampoline'

# 7) No start "title" orphan cmd pattern
Assert ($launch -notmatch 'start "Claude Connect" /D') `
    'instant launcher must not use titled start /D powershell (orphan cmd)'

# 8) No install MessageBox on happy path
Assert ($launch -match 'Remove-Item Env:CLAUDE_CONNECT_SHOW_INSTALL_NOTICE' -and $worker -match 'no install MessageBox') `
    'setup clears install-notice env; worker has no install MessageBox'

# 9) Fast path direct boot (skip worker when src complete)
Assert ($launch -match 'if \(\$complete -and -not \$didInstall\)' -and $launch -match 'setup ok fast_path direct_boot') `
    'fast_path boots connect-boot directly when src already complete'

# 10) Worker never auto-updates (manual menu u only)
Assert ($worker -match 'preboot update skipped reason=manual_only') `
    'worker skips preboot update (manual_only)'
Assert ($worker -notmatch 'CLAUDE_CONNECT_UPDATE_YES\s*=\s*''1''') `
    'worker does not set CLAUDE_CONNECT_UPDATE_YES=1'

# 11) Unblock-File MOTW on installed scripts (launch + worker)
Assert ($launch -match 'Unblock-File' -and $worker -match 'Unblock-File') `
    'setup-launch and setup-worker call Unblock-File on client scripts'

# 12) Client-only ZIP: no server/ tree
Assert ($publish -match 'function Assert-ClientPackage' -and $publish -match "Filter 'server'") `
    'publish.ps1 Assert-ClientPackage forbids server/ in client packages'

# 13) Sepidz IP patch 240 -> 70
Assert ($publish -match "192\.168\.210\.240" -and $publish -match "192\.168\.250\.70" -and $publish -match '\[regex\]::Escape\(\$FromIp\)') `
    'publish.ps1 patches Smart IP 192.168.210.240 -> Sepidz 192.168.250.70'

# 14) 12-file package invariants (if manifest present)
$manifestPath = Join-Path $RepoRoot 'publish\client-bundle-manifest.tsv'
if (Test-Path -LiteralPath $manifestPath) {
    $manifestLines = @(Get-Content -LiteralPath $manifestPath | Where-Object {
        $_.Trim() -and -not $_.TrimStart().StartsWith('#')
    })
    $coreTwelve = @(
        'connect.bat', 'connect.ps1', 'connect-boot.ps1', 'connect-update.ps1', 'connect-version.txt',
        'git-mode.ps1', 'editor-launch.ps1', 'connect-ui.ps1',
        'connect.sh', 'git-mode.sh', 'connect-ui.sh', 'editor-launch.sh'
    )
    $manifestNames = @($manifestLines | ForEach-Object { ($_ -split "`t")[1].Trim() })
    $missing = @($coreTwelve | Where-Object { $manifestNames -notcontains $_ })
    Assert ($missing.Count -eq 0) `
        ("client-bundle-manifest lists 12 core handoff files (missing: {0})" -f ($missing -join ', '))
} else {
    Write-Host '  SKIP  client-bundle-manifest.tsv not present (12-file gate optional)' -ForegroundColor DarkYellow
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} publish/IExpress hard-batch gates passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
