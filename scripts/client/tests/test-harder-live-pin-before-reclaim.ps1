#Requires -Version 5.1
# test-harder-live-pin-before-reclaim.ps1 (L3)
# Ensure OrphanReclaim before adopt_local_forward; RECLAIM_PIN preferred_port;
# preferred keep pins even when editor check false (code comment/path).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== HARDER LIVE L3: pin-before-reclaim / Ensure order ===' -ForegroundColor Cyan

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$ensureSrc = Get-FunctionSource -Content $gm -Name 'Ensure-SessionTunnel'
$reclaimSrc = Get-FunctionSource -Content $gm -Name 'Invoke-ConnectOrphanReclaim'
$acqSrc = Get-FunctionSource -Content $gm -Name 'Acquire-ConnectTunnelSlot'
if (-not $acqSrc) {
    # Name may vary; fall back to content search for Acquire function
    $m = [regex]::Match($gm, 'function\s+(Acquire-\w*[Tt]unnel\w*|Get-ConnectTunnelSlot)\b')
    if ($m.Success) { $acqSrc = Get-FunctionSource -Content $gm -Name $m.Groups[1].Value }
}

Assert ([bool]$ensureSrc) 'extracted Ensure-SessionTunnel'
Assert ([bool]$reclaimSrc) 'extracted Invoke-ConnectOrphanReclaim'

# Ensure: OrphanReclaim before adopt_local_forward
$idxReclaim = $ensureSrc.IndexOf('Invoke-ConnectOrphanReclaim')
$idxAdopt = $ensureSrc.IndexOf('adopt_local_forward')
Assert ($idxReclaim -ge 0) 'Ensure calls Invoke-ConnectOrphanReclaim'
Assert ($idxAdopt -ge 0) 'Ensure has adopt_local_forward path'
Assert (($idxReclaim -ge 0) -and ($idxAdopt -ge 0) -and ($idxReclaim -lt $idxAdopt)) `
    'Ensure OrphanReclaim BEFORE adopt_local_forward'

Assert ($ensureSrc -match 'OrphanReclaimDoneThisEnsure') 'Ensure once-per-flag OrphanReclaimDoneThisEnsure'
Assert ($ensureSrc -match 'PreferredPort') 'Ensure passes PreferredPort to reclaim'

# RECLAIM_PIN preferred_port
Assert ($reclaimSrc -match 'RECLAIM_PIN preferred_port=') 'RECLAIM_PIN preferred_port log present'
Assert ($reclaimSrc -match 'preferred_pin|PreferredPort') 'preferred pin path in reclaim'

# Preferred keep pins even when editor check false (comment + code path)
Assert ($reclaimSrc -match 'even if editor check is false|editor check is false') `
    'comment: pin preferred even when editor check false'
Assert ($reclaimSrc -match 'reason=preferred_pin') 'RECLAIM_SKIP_KEEP reason=preferred_pin'
# Path: PreferredPort keep → keepProtect=$true without requiring Test-ConnectKeepEditorProtect true
Assert ($reclaimSrc -match '(?s)PreferredPort[\s\S]{0,400}preferred_pin|preferred_pin[\s\S]{0,200}SkippedKeep') `
    'preferred_pin sets keep protect / SkippedKeep'

# Acquire also pins keep_editor when editor_check=0
Assert ($gm -match 'editor_check=0') 'Acquire keep_editor path logs editor_check=0'
Assert ($gm -match 'ACQUIRE_SKIP: keep_editor') 'Acquire skips keep_editor ports'

Write-Host ''
$col = if ($Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("L3 pin-before-reclaim RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $col
if ($Fail -gt 0) { exit 1 }
exit 0
