#Requires -Version 5.1
# test-client-update-policy-optional.ps1 - Stage 6b: optional policy + Quiet never force + hard-refuse
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ""
Write-Host "=== client-update-policy optional (Stage 6b) ==="
Write-Host ""

$policyPath = Join-Path $RepoRoot 'scripts\server\client-update-policy.json'
Assert (Test-Path -LiteralPath $policyPath) 'client-update-policy.json exists'
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
Assert ([string]$policy.mode -eq 'optional') 'policy mode is optional'
Assert ([string]$policy.latest -eq '20260722.40') 'policy latest is 20260722.40'
$minRaw = $null
try { $minRaw = $policy.force_min_version } catch { $minRaw = $null }
$minStr = if ($null -eq $minRaw) { '' } else { [string]$minRaw }
Assert ([string]::IsNullOrWhiteSpace($minStr) -or $minStr -eq 'null') 'policy force_min_version is null/empty'
Assert ($null -ne $policy.defer_hours) 'policy keeps defer_hours'
Assert (-not [string]::IsNullOrWhiteSpace([string]$policy.message_optional)) 'policy keeps message_optional'

$upd = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-update.ps1') -Raw
$conn = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect.ps1') -Raw
$pub = Get-Content (Join-Path $RepoRoot 'publish\publish.ps1') -Raw

# Prompt catch / empty default N (not Y) — single-quoted needles so $ is literal
Assert ($upd.Contains('} catch { $answer = ''N'' }')) 'connect-update prompt catch defaults to N'
Assert ($upd.Contains('if (-not $answer) { $answer = ''N'' }')) 'connect-update empty answer defaults to N'
Assert (-not $upd.Contains('} catch { $answer = ''Y'' }')) 'connect-update catch no longer defaults to Y'

# Quiet + optional never UPDATE_FORCE / applied_ok unless force mode AND force_min
Assert ($upd.Contains('Test-UpdateForceRequired')) 'connect-update still uses Test-UpdateForceRequired'
Assert ($upd.Contains('$forceApply = ($mode -eq ''force'') -and $forceReq')) 'UPDATE_FORCE gated on mode force AND force_min (forceReq)'
Assert ($upd.Contains('UPDATE_OPTIONAL_SKIP reason=silent')) 'Quiet optional path logs UPDATE_OPTIONAL_SKIP'
Assert ($upd.Contains('if ($script:Quiet)')) 'Quiet branch present before optional apply'
Assert ($upd.Contains('if (-not $forceApply)')) 'optional/Quiet path uses -not forceApply (no force without min)'

# Hard-refuse: sepidz path / .70 on Smart
$refuseHay = $upd + "`n" + $conn
Assert ($refuseHay.Contains('claude-code-sepidz')) 'hard-refuse mentions claude-code-sepidz'
Assert ($refuseHay.Contains('claude-connect-sepidz') -or $refuseHay.Contains('Claude-Connect-Sepidz')) 'hard-refuse mentions Claude-Connect-Sepidz'
Assert ($refuseHay.Contains('192.168.250.70')) 'hard-refuse mentions Sepidz IP .70'
Assert ($refuseHay.Contains('REFUSE Smart/Sepidz contamination')) 'hard-refuse FAIL/REFUSE marker present in connect.ps1 or connect-update.ps1'
Assert ($conn.Contains('claude-code-sepidz') -or $conn.Contains('Claude-Connect-Sepidz')) 'connect.ps1 has Smart hard-refuse path check'
Assert ($upd.Contains('claude-code-sepidz') -or $upd.Contains('Claude-Connect-Sepidz')) 'connect-update.ps1 has Smart hard-refuse path check'

# Publish: Smart folder keeps scripts (no post-ZIP EXE-only strip for handoff)
Assert ($pub.Contains('Clear-PublishedWindowsToExeOnly')) 'publish.ps1 still defines Clear-PublishedWindowsToExeOnly'
Assert ($pub.Contains('CLAUDE_PUBLISH_STRIP_WINDOWS_EXE_ONLY')) 'Smart publish gates EXE-only strip behind env flag'
Assert ($pub.Contains('keeps full script tree')) 'Smart publish documents full script tree retention'
Assert (Test-Path (Join-Path $RepoRoot 'publish\SEPIDZ_PUBLISH_FROZEN')) 'SEPIDZ_PUBLISH_FROZEN marker still present'

# Mac optional prompt parity (Stage 6b)
$macUpd = Get-Content (Join-Path $RepoRoot 'scripts\client\mac\connect-update.sh') -Raw
Assert ($macUpd -match '\[y/N/D\]') 'Mac optional prompt shows [y/N/D]'
Assert ($macUpd -match '(?m)^\s*ans=N\s*$') 'Mac optional ans defaults to N'
Assert ($macUpd -match '\[ -z "\$ans" \] && ans=N') 'Mac empty Enter keeps N'
Assert (([regex]::Matches($macUpd, 'Optional update available[\s\S]{0,200}\[y/N/D\]')).Count -ge 1) 'Mac optional block uses [y/N/D]'

Write-Host ""
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
