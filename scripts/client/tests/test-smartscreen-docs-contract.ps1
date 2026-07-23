#Requires -Version 5.1
# test-smartscreen-docs-contract.ps1 - Stage 6c: folder-primary + SmartScreen/Defender FP docs
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ""
Write-Host "=== smartscreen / Defender FP docs (Stage 6c) ==="
Write-Host ""

$doc = Get-Content (Join-Path $RepoRoot 'docs\client-connect.md') -Raw
$readme = Get-Content (Join-Path $RepoRoot 'publish\README.txt') -Raw
$build = Get-Content (Join-Path $RepoRoot 'publish\build-windows-exe.ps1') -Raw
$hay = $doc + "`n" + $readme

# Folder / ZIP is primary handoff
Assert ($hay -match '(?i)folder.?primary|primary.*(folder|ZIP)|Primary handoff is the \*\*folder\*\*') 'docs state folder/ZIP primary handoff'
Assert ($readme -match '(?i)folder|ZIP') 'README mentions folder or ZIP'
Assert ($readme -match '(?i)primary') 'README marks folder/ZIP as primary'
Assert (-not ($readme -match '(?i)Option A \(single file — preferred')) 'README no longer prefers EXE-only Option A'

# SmartScreen / Defender false-positive guidance
Assert ($hay -match 'SmartScreen') 'docs mention SmartScreen'
Assert ($hay -match '(?i)Defender') 'docs mention Defender'
Assert ($hay -match '(?i)false.?positive|incorrectly (classified|detected)') 'docs mention false positive'
Assert ($hay -match '(?i)IExpress|unsigned') 'docs mention unsigned IExpress EXE risk'
Assert ($hay -match '(?i)Unblock|Mark of the Web|MOTW') 'docs mention Allow/Unblock MOTW'
Assert ($hay -match '(?i)Desktop\\Claude-Connect') 'docs scope exclusion to Desktop\Claude-Connect'
Assert ($hay -match '(?i)exclusion|exclude') 'docs mention scoped exclusion'
Assert ($hay -match '(?i)Authenticode') 'docs mention Authenticode'
Assert ($hay -match '(?i)OV.*(cert|code-signing)|code-signing.*OV') 'docs mention OV code-signing'
Assert ($hay -match '(?i)RFC 3161 timestamp') 'docs mention RFC 3161 timestamp'
Assert ($hay -match 'wdsi/filesubmission|microsoft\.com/en-us/wdsi') 'docs link WDSI submission'

# Never advise disabling Defender
# Allow "never/do not disable Defender"; forbid advice/API that turns it off
Assert (-not ($hay -match '(?i)Set-MpPreference\s+-DisableRealtimeMonitoring\s+\$true')) 'docs never suggest Set-MpPreference DisableRealtime'
Assert (-not ($hay -match '(?i)you should disable (Windows |Microsoft )?Defender|please disable (Windows |Microsoft )?Defender|disable Defender to (fix|solve|work)')) 'docs never advise disabling Defender'
Assert (-not ($build -match '(?i)Set-MpPreference|DisableRealtimeMonitoring')) 'build-windows-exe never disables Defender via Set-MpPreference'
Assert ($hay -match '(?i)never.*disable.*(Defender|SmartScreen)|do not disable Defender|NEVER disable Microsoft Defender') 'docs explicitly forbid disabling Defender'

# Optional pointer in build script
Assert ($build -match '(?i)client-connect\.md|SmartScreen|false.?positive') 'build-windows-exe.ps1 comments point at FP docs'

Write-Host ""
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
