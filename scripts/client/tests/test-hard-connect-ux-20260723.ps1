#Requires -Version 5.1
# test-hard-connect-ux-20260723.ps1
# Adversarial HARD gate for connect Windows UX/perf (Tasks 1-7).
# Mutation-style: if a fix regresses, these fail. Do not ship on FAIL.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== HARD connect UX/perf adversarial (20260723.13) ===' -ForegroundColor White

$win   = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.ps1') -Raw
$bat   = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.bat') -Raw
$boot  = Get-Content -LiteralPath (Get-ClientFile 'windows\connect-boot.ps1') -Raw
$el    = Get-Content -LiteralPath (Get-ClientFile 'editor-launch.ps1') -Raw
$ui    = Get-Content -LiteralPath (Get-ClientFile 'connect-ui.ps1') -Raw
$uiSh  = Get-Content -LiteralPath (Get-ClientFile 'connect-ui.sh') -Raw
$verTxt = (Get-Content -LiteralPath (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
$macVerPath = Join-Path (Split-Path (Get-ClientFile 'windows\connect.ps1') -Parent) '..\mac\connect-version.txt'
$macVer = if (Test-Path $macVerPath) { (Get-Content -LiteralPath $macVerPath -Raw).Trim() } else { '' }

$repoRoot = Resolve-Path (Join-Path (Split-Path (Get-ClientFile 'windows\connect.ps1') -Parent) '..\..\..')
$mountPath = Join-Path $repoRoot 'scripts\server\claude-mount.sh'
$mount = if (Test-Path $mountPath) { Get-Content -LiteralPath $mountPath -Raw } else { '' }

Write-Host '--- V) Version lockstep ---' -ForegroundColor Cyan
# Lockstep, not a frozen literal: the three version sources must AGREE with each other. Hardcoding
# a specific version here just rots on every legitimate version bump (it broke on 20260725.x). Use
# connect.ps1's ConnectVersion as the single source of truth and assert the others match it.
$winVer = if ($win -match "ConnectVersion = '([^']+)'") { $Matches[1] } else { '' }
Assert ($winVer -ne '') 'connect.ps1 ConnectVersion present'
Assert ($verTxt -eq $winVer) ("connect-version.txt lockstep with connect.ps1 (txt='$verTxt' ps1='$winVer')")
Assert (($macVer -eq $winVer) -or ($macVer -eq '')) ("mac connect-version.txt lockstep (got '$macVer' expected '$winVer')")

Write-Host '--- T1) Mount fail-fast ---' -ForegroundColor Cyan
Assert ($win -match 'function SshX\(\[string\]\$Cmd, \[switch\]\$NoRetryOnTimeout\)') 'SshX has NoRetryOnTimeout'
Assert ($win -match 'Exit -eq 124 -and -not \$NoRetryOnTimeout') 'SshX skips timeout retry when NoRetryOnTimeout'
Assert ($win -match '\$skipRemount = \[bool\]\$recoverCheckOk|\$skipRemount = \$recoverCheckOk') 'skipRemount reuses recoverCheckOk'
if ($mount) {
    Assert ($mount -match 'timeout -k 1 2') 'claude-mount uses timeout -k for hung FUSE ls'
} else {
    Write-Host '  WARN  claude-mount.sh not resolved' -ForegroundColor DarkYellow
}

Write-Host '--- T2) Quiet bat / preflight ---' -ForegroundColor Cyan
$pre = Get-ClientFile 'windows\connect-preflight.ps1'
Assert (Test-Path $pre) 'connect-preflight.ps1 present'
Assert ($bat -match 'connect-preflight\.ps1') 'bat references preflight'
Assert ($bat -notmatch '-WindowStyle Hidden[^\r\n]*-File[^\r\n]*connect\.ps1') 'bat does not Hidden -File connect.ps1'
Assert ($bat -match 'Starting Claude Connect\.\.\.') 'bat Starting Claude Connect without UAC nag'
Assert ($bat -notmatch 'accept UAC') 'accept UAC echo removed'

Write-Host '--- T3) Elevate-when-needed ---' -ForegroundColor Cyan
$early = $win.Substring(0, [Math]::Min(4500, $win.Length))
Assert ($early -notmatch 'Verb RunAs') 'cold-start header: no Verb RunAs'
Assert ($win -match 'Elevate-when-needed') 'elevate-when-needed documented'
Assert ($win -notmatch 'Always elevate the main connect UI') 'always-elevate block gone'
Assert ($boot -match 'connect\.ps1') 'connect-boot still launches connect.ps1'
Assert ($win -match '\[switch\]\$AdminFix') 'AdminFix retained'

Write-Host '--- T4) Quiet Cursor / non-admin prefer ---' -ForegroundColor Cyan
Assert ($el -match 'cursor-launch-') 'cursor-launch log path present'
Assert ($el -match 'elevated_direct_fallback') 'elevated_direct_fallback last resort present'
$neAt = $el.IndexOf('NonElevatedLauncher')
$taskAt = $el.IndexOf('/RL LIMITED'); if ($taskAt -lt 0) { $taskAt = $el.IndexOf('RL LIMITED') }
$directAt = $el.IndexOf('elevated_direct_fallback')
Assert ($neAt -ge 0 -and $taskAt -gt $neAt -and $directAt -gt $taskAt) 'launch order NE then LIMITED then elevated_direct'

Write-Host '--- T5) Sticky conf / no wipe ---' -ForegroundColor Cyan
Assert ($win -match 'function Save-ConnectConfKey') 'Save-ConnectConfKey present'
Assert ($win -notmatch '@\("REMOTE_USER=\$') 'no two-key REMOTE_USER wipe arrays'
Assert ($win -match 'Save-ConnectConfKey -Path \$Cfg -Key') 'username paths call Save-ConnectConfKey'
$tmp = Join-Path $env:TEMP ('hard-ux-conf-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$cfg = Join-Path $tmp 'connect.conf'
@"
REMOTE_USER=testsmart
LAPTOP_USER=Smart
GIT_MODE=hide
TUNNEL_SLOT=2
PORT=20021
EXTRA_KEY=keepme
"@ | Set-Content -Path $cfg -Encoding ASCII
$m = [regex]::Match($win, '(?ms)^function\s+Save-ConnectConfKey\b.*')
Assert ($m.Success) 'extract Save-ConnectConfKey for runtime'
if ($m.Success) {
    $lines = $m.Value -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $depth = 0
    foreach ($line in $lines) {
        [void]$out.Add($line)
        $depth += ([regex]::Matches($line, '\{')).Count
        $depth -= ([regex]::Matches($line, '\}')).Count
        if ($depth -le 0 -and $out.Count -gt 1) { break }
    }
    $fn = Join-Path $tmp 'h.ps1'
    ($out -join "`n") | Set-Content -Path $fn -Encoding UTF8
    . $fn
    Save-ConnectConfKey -Path $cfg -Key 'REMOTE_USER' -Value 'smart'
    $map = @{}
    Get-Content $cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $map[$Matches[1]] = $Matches[2] } }
    Assert ($map['REMOTE_USER'] -eq 'smart') 'runtime: REMOTE_USER -> smart'
    Assert ($map['EXTRA_KEY'] -eq 'keepme') 'runtime: EXTRA_KEY preserved'
    Assert ($map['GIT_MODE'] -eq 'hide') 'runtime: GIT_MODE preserved'
    Assert ($map['TUNNEL_SLOT'] -eq '2') 'runtime: TUNNEL_SLOT preserved'
    Save-ConnectConfKey -Path $cfg -Key 'LAPTOP_USER' -Value 'Smart'
    $map2 = @{}
    Get-Content $cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $map2[$Matches[1]] = $Matches[2] } }
    Assert ($map2['EXTRA_KEY'] -eq 'keepme') 'runtime: second save still preserves EXTRA_KEY'
    Assert ($map2.Count -ge 6) 'runtime: key count >= 6 after two saves'
}
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

Write-Host '--- T6) Quieter logs + auth skip enum ---' -ForegroundColor Cyan
Assert ($ui -match '\[DEBUG\].*LOG_SYNC_SKIP reason=forbid_shrink') 'forbid_shrink is DEBUG on Win'
Assert ($ui -notmatch '\[INFO\].*LOG_SYNC_SKIP reason=forbid_shrink') 'forbid_shrink not INFO on Win'
Assert ($uiSh -match "forbid_shrink[^\r\n]*'DEBUG'") 'forbid_shrink DEBUG on Mac'
Assert ($win -match '(?s)\$skipAuth = \$false.*?-not \$skipAuth -and \(Get-Command Test-PersonalCursorDominant') 'PersonalCursorDominant gated on -not skipAuth'

Write-Host '--- X) Mutation / anti-regression ---' -ForegroundColor Cyan
Assert ($win -notmatch '(?s)if \(-not \$script:RunAdminFix\).*Verb RunAs') 'mutation: cold-start RunAdminFix elevate loop gone'
Assert ($bat -match 'connect-boot\.ps1') 'bat still handoffs connect-boot'

Write-Host ''
if ($failed -gt 0) {
    Write-Host "HARD UX FAIL: $failed failed / $passed passed" -ForegroundColor Red
    exit 1
}
Write-Host "HARD UX PASS: $passed checks" -ForegroundColor Green
exit 0
