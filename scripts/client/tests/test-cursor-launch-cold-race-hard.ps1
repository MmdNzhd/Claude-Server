# test-cursor-launch-cold-race-hard.ps1
#
# Fleet 2026-08-03 deep-parallel W1+W2:
#   both LAUNCH_PLAN use_new_window=False reason=cold_start profile_all=0 at the same ms
# Shared ClaudeServerCursorProfile: two cold starts without --new-window race the profile.
# Contract: cross-process launch gate; waiter re-queries profile and may become profile_open.
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert-C([string]$id, [bool]$ok, [string]$title, [string]$detail) {
  if ($ok) { Write-Host "PASS  [$id] $title"; Write-Host "      $detail" }
  else { Write-Host "HARD FAIL  [$id] $title"; Write-Host "      $detail"; $script:fail++ }
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts/client/editor-launch.ps1'))) {
  $RepoRoot = 'D:\Smart\Claude-Code-Server'
}
$elPath = Join-Path $RepoRoot 'scripts/client/editor-launch.ps1'
$elSh = Join-Path $RepoRoot 'scripts/client/editor-launch.sh'
$el = Get-Content -LiteralPath $elPath -Raw
$sh = if (Test-Path -LiteralPath $elSh) { Get-Content -LiteralPath $elSh -Raw } else { '' }

Write-Host '=== cursor cold-start launch race hard ==='
Write-Host ("root={0}" -f $RepoRoot)
Write-Host ''

Assert-C 'S1' ($el -match 'function Enter-CursorProfileLaunchGate') 'Enter-CursorProfileLaunchGate defined' 'ok'
Assert-C 'S2' ($el -match 'function Exit-CursorProfileLaunchGate') 'Exit-CursorProfileLaunchGate defined' 'ok'
Assert-C 'S3' ($el -match 'ClaudeConnectCursorLaunch') 'Global mutex name ClaudeConnectCursorLaunch' 'ok'
Assert-C 'S4' ($el -match '(?s)\$launchGate\s*=\s*Enter-CursorProfileLaunchGate[\s\S]{0,3500}?LAUNCH_PLAN') 'gate acquired before LAUNCH_PLAN' 'ok'
Assert-C 'S5' ($el -match 'LAUNCH_GATE') 'LAUNCH_GATE log marker present' 'ok'
Assert-C 'S6' ($sh -match '_cursor_launch_gate_enter|_cursor_profile_launch_gate') 'Mac launch gate helper present' 'ok'
# Deep gap (fleet after first gate): settle must run when WaitedMs>0 even if profile_all=0;
# belt forces --new-window if still cold after wait (launch_gate_peer).
Assert-C 'S7' ($el -match 'gateWaited' -and $el -match 'LAUNCH_GATE_SETTLE' -and ($el -notmatch 'WaitedMs -gt 0\)\s+-and\s+\(-not \$hasProfileWindow\)\s+-and\s+\(\$profileProcCount -gt 0\)')) 'settle not gated on profile_all>0' 'ok'
Assert-C 'S8' ($el -match 'launch_gate_peer' -and $el -match 'LAUNCH_GATE_PEER') 'peer belt forces new-window after wait' 'ok'
Assert-C 'S9' ($sh -match '_CURSOR_LAUNCH_GATE_WAITED' -and $sh -match 'launch_gate_peer') 'Mac waited flag + peer belt' 'ok'
Assert-C 'S10' ($el -match 'for \(\$settle = 1; \$settle -le 12' -or $el -match 'settle -le 12') 'settle budget >=12 ticks after wait' 'ok'
Assert-C 'S11' ($el -match 'LAUNCH_REAP_SKIP' -and $el -match 'Contended') 'gate wait skips orphan reap + Contended flag' 'ok'
Assert-C 'S12' ($sh -match 'LAUNCH_REAP_SKIP' -and $sh -match '_CURSOR_LAUNCH_GATE_WAITED=1') 'Mac timeout sets WAITED + skip reap' 'ok'

# Live mutex: holder blocks waiter until release; waiter WaitedMs > 0
. $elPath
$holder = Enter-CursorProfileLaunchGate -TimeoutMs 2000
Assert-C 'L1' ([bool]$holder.Acquired) 'L1: first Enter acquires' ("acquired=$($holder.Acquired)")

$waiterJob = Start-Job -ScriptBlock {
  param($ElPath)
  . $ElPath
  $w = Enter-CursorProfileLaunchGate -TimeoutMs 8000
  [pscustomobject]@{ Acquired = [bool]$w.Acquired; WaitedMs = [int]$w.WaitedMs }
  Exit-CursorProfileLaunchGate -Gate $w
} -ArgumentList $elPath

# Job startup + WaitOne handoff can chew ~200ms; hold >=900ms so WaitedMs stays clearly above floor.
Start-Sleep -Milliseconds 900
Exit-CursorProfileLaunchGate -Gate $holder
$waiter = Wait-Job $waiterJob -Timeout 15 | Receive-Job
Remove-Job $waiterJob -Force -ErrorAction SilentlyContinue
Assert-C 'L2' ($null -ne $waiter -and $waiter.Acquired) 'L2: waiter acquires after holder release' ("acquired=$($waiter.Acquired)")
Assert-C 'L3' ($null -ne $waiter -and [int]$waiter.WaitedMs -ge 300) 'L3: waiter actually waited (serialized)' ("WaitedMs=$($waiter.WaitedMs)")

# Plan contract unchanged: cold vs profile_open
$planCold = Get-CursorLaunchWindowPlan -AgentHome $false -HasProfileWindow $false -ProfileProcCount 0
$planOpen = Get-CursorLaunchWindowPlan -AgentHome $false -HasProfileWindow $true -ProfileProcCount 11
Assert-C 'L4' ($planCold.Reason -eq 'cold_start' -and -not $planCold.UseNewWindow) 'L4: true cold stays cold_start' ("reason=$($planCold.Reason)")
Assert-C 'L5' ($planOpen.Reason -eq 'profile_open' -and $planOpen.UseNewWindow) 'L5: after peer open -> profile_open + new-window' ("reason=$($planOpen.Reason)")

Write-Host ''
Write-Host ("=== RESULT fail={0} ===" -f $fail)
if ($fail -gt 0) { Write-Host 'VERDICT: FAIL'; exit 1 }
Write-Host 'VERDICT: PASS'
exit 0
