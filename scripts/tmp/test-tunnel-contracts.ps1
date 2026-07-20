# test-tunnel-contracts.ps1 — HARD tunnel softfail/banner/recover contracts
# Exit 1 on any miss.
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Client = Join-Path $Root 'scripts\client'
$fail = 0
$passes = 0

function Pass([string]$Msg) {
    Write-Host "  PASS  $Msg" -ForegroundColor Green
    $script:passes++
}
function Fail([string]$Msg, [string]$Detail = '') {
    Write-Host "  FAIL  $Msg" -ForegroundColor Red
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
    $script:fail++
}
function Get-FunctionBody([string[]]$Lines, [string]$NamePattern) {
    $hit = $Lines | Select-String -Pattern $NamePattern | Select-Object -First 1
    if (-not $hit) { return $null }
    $i = $hit.LineNumber - 1
    $depth = 0
    $end = $i
    for ($j = $i; $j -lt $Lines.Count; $j++) {
        $depth += ([regex]::Matches($Lines[$j], '\{')).Count
        $depth -= ([regex]::Matches($Lines[$j], '\}')).Count
        $end = $j
        if ($j -gt $i -and $depth -le 0) { break }
    }
    return ($Lines[$i..$end] -join "`n")
}

$winGit = Join-Path $Client 'git-mode.ps1'
$macGit = Join-Path $Client 'git-mode.sh'
$winConn = Join-Path $Client 'windows\connect.ps1'
Write-Host "Root=$Root"

foreach ($p in @($winGit, $macGit, $winConn)) {
    if (-not (Test-Path -LiteralPath $p)) { Fail "missing file $p"; exit 1 }
}

$lines = Get-Content -LiteralPath $winGit
$macLines = Get-Content -LiteralPath $macGit
$connRaw = Get-Content -LiteralPath $winConn -Raw

Write-Host '=== Tunnel softfail / banner / recover contracts ===' -ForegroundColor Cyan

# --- 1) Win SoftFailCount -ge 6 => DROP/false (no_proc path must not soft-continue forever) ---
if (@(Select-String -LiteralPath $winGit -Pattern 'TunnelSoftFailCount -ge 6' -SimpleMatch).Count -gt 0) {
    Pass 'Win: SoftFailCount budget threshold (-lt 6) present'
} else {
    Fail 'Win: SoftFailCount budget threshold (-lt 6) present'
}

$noProcHit = @(Select-String -LiteralPath $winGit -Pattern 'reason=no_proc_tcp_open' -SimpleMatch)
if ($noProcHit.Count -eq 0) {
    Fail 'Win: SoftFailCount -ge 6 leads to TUNNEL_DROP or return $false' 'no_proc_tcp_open missing'
} else {
    $n = $noProcHit[0].LineNumber - 1
    # Include SoftFail++ line above through ~20 lines
    $start = [Math]::Max(0, $n - 3)
    $chunk = ($lines[$start..([Math]::Min($start + 22, $lines.Count - 1))] -join "`n")
    # Exhausted budget in THIS no_proc block must DROP or return false (not fall through only)
    $hasBudgetContinue = $chunk -match 'TunnelSoftFailCount -ge 6'
    $hasHard = ($chunk -match 'TunnelSoftFailCount -ge 6') -and (($chunk -match 'TUNNEL_DROP') -or ($chunk -match 'return \$false'))
    if (-not $hasHard) {
        # else branch after -lt 6 with DROP/false
        $hasHard = $chunk -match '(?s)TunnelSoftFailCount -ge 6[\s\S]{0,80}else[\s\S]{0,200}(TUNNEL_DROP|return \$false)'
    }
    if ($hasBudgetContinue -and $hasHard) {
        Pass 'Win: SoftFailCount -ge 6 leads to TUNNEL_DROP or return $false'
    } else {
        Fail 'Win: SoftFailCount -ge 6 leads to TUNNEL_DROP or return $false' 'no_proc path: -lt 6 soft-continues; exhausted budget has no DROP/false'
    }
}

if (@(Select-String -LiteralPath $macGit -Pattern 'no_ssh_proc_tcp_open_budget' -SimpleMatch).Count -gt 0) {
    Pass 'Mac: SoftFail budget emits TUNNEL_DROP (no_ssh_proc_tcp_open_budget)'
} else {
    Fail 'Mac: SoftFail budget emits TUNNEL_DROP (no_ssh_proc_tcp_open_budget)'
}

# --- 2) banner_miss budgets toward DROP (Win+Mac) ---
if (@(Select-String -LiteralPath $winGit -Pattern 'banner_miss_tcp_open' -SimpleMatch).Count -gt 0) {
    Pass 'Win: banner_miss_tcp_open present'
} else { Fail 'Win: banner_miss_tcp_open present' }
if (@(Select-String -LiteralPath $macGit -Pattern 'banner_miss_tcp_open' -SimpleMatch).Count -gt 0) {
    Pass 'Mac: banner_miss_tcp_open present'
} else { Fail 'Mac: banner_miss_tcp_open present' }

$winBanBudget = @(Select-String -LiteralPath $winGit -Pattern 'banner_miss_tcp_open_budget' -SimpleMatch)
$winBanInc = @(Select-String -LiteralPath $winGit -Pattern 'TUNNEL_SYNC soft_fail count=.*banner_miss_tcp_open')
if ($winBanBudget.Count -gt 0 -and $winBanInc.Count -gt 0) {
    Pass 'Win: banner_miss budgets toward DROP'
} else {
    Fail 'Win: banner_miss budgets toward DROP' "budgetLog=$($winBanBudget.Count) syncInc=$($winBanInc.Count)"
}

$macBanBudget = @(Select-String -LiteralPath $macGit -Pattern 'banner_miss_tcp_open_budget' -SimpleMatch)
$macBanInc = @(Select-String -LiteralPath $macGit -Pattern 'TUNNEL_SYNC soft_fail count=.*banner_miss_tcp_open')
if ($macBanBudget.Count -gt 0 -and $macBanInc.Count -gt 0) {
    Pass 'Mac: banner_miss budgets toward DROP'
} else {
    Fail 'Mac: banner_miss budgets toward DROP' "budgetLog=$($macBanBudget.Count) syncInc=$($macBanInc.Count)"
}

# --- 3) Ensure* must NOT return success solely on banner_miss_tcp_open ---
$ensWin = @(Select-String -LiteralPath $winGit -Pattern 'ENSURE_TUNNEL soft_fail.*banner_miss_tcp_open')
if ($ensWin.Count -eq 0) {
    Fail 'Win Ensure-SessionTunnel does NOT return success solely on banner_miss_tcp_open' 'ENSURE banner_miss missing'
} else {
    $n = $ensWin[0].LineNumber - 1
    $next = ($lines[$n..([Math]::Min($n + 4, $lines.Count - 1))] -join "`n")
    $soleSuccess = ($next -match 'return \$true') -and ($next -notmatch 'action=reseed')
    # Also fail if return $true appears before any fall-through / kill / start
    $immediateReturn = [regex]::IsMatch($next, 'banner_miss_tcp_open[^\n]*\n[^\n]*return \$true')
    if ($immediateReturn -or $soleSuccess) {
        Fail 'Win Ensure-SessionTunnel does NOT return success solely on banner_miss_tcp_open' 'return $true right after banner_miss'
    } else {
        Pass 'Win Ensure-SessionTunnel does NOT return success solely on banner_miss_tcp_open'
    }
}

$ensMac = @(Select-String -LiteralPath $macGit -Pattern 'ENSURE_TUNNEL soft_fail.*banner_miss_tcp_open')
if ($ensMac.Count -eq 0) {
    Fail 'Mac ensure_session_tunnel does NOT return success solely on banner_miss_tcp_open' 'ENSURE banner_miss missing'
} else {
    $n = $ensMac[0].LineNumber - 1
    $next = ($macLines[$n..([Math]::Min($n + 5, $macLines.Count - 1))] -join "`n")
    $immediateReturn = [regex]::IsMatch($next, 'banner_miss_tcp_open[^\n]*\n(?:[^\n]*\n){0,3}[^\n]*return 0')
    if ($immediateReturn) {
        Fail 'Mac ensure_session_tunnel does NOT return success solely on banner_miss_tcp_open' 'return 0 right after banner_miss'
    } else {
        Pass 'Mac ensure_session_tunnel does NOT return success solely on banner_miss_tcp_open'
    }
}

# --- 4) Mac wait_for_tunnel seq 1 12 ---
$wf = Get-FunctionBody -Lines $macLines -NamePattern '^wait_for_tunnel_up\(\)'
if (-not $wf) {
    Fail 'Mac wait_for_tunnel uses seq 1 12 or -le 12' 'missing wait_for_tunnel_up'
} elseif (($wf -match 'seq\s+1\s+12') -or ($wf -match '-le\s+12')) {
    Pass 'Mac wait_for_tunnel uses seq 1 12 or -le 12'
} else {
    Fail 'Mac wait_for_tunnel uses seq 1 12 or -le 12' (($wf -split "`n" | Select-String 'seq |for ' | ForEach-Object { $_.Line.Trim() }) -join '; ')
}

# --- 5) recover: single remote sshx; no nested sshx ---
$rf = Get-FunctionBody -Lines $macLines -NamePattern '^recover_mounts_if_needed\(\)'
if (-not $rf) {
    Fail 'Mac recover_mounts_if_needed: single remote command; no nested sshx' 'missing function'
} else {
    Pass 'Mac: recover_mounts_if_needed body captured'
    $recoverLines = @($rf -split "`n" | Where-Object { $_ -match 'sshx' -and $_ -match 'recover' })
    $nested = $false
    foreach ($line in $recoverLines) {
        if (([regex]::Matches($line, '\bsshx\b')).Count -gt 1) { $nested = $true }
        if ($line -match 'sshx\s+".*sshx') { $nested = $true }
    }
    if ($recoverLines.Count -ge 1 -and -not $nested) {
        Pass 'Mac recover_mounts_if_needed: single remote command; no nested sshx'
    } else {
        Fail 'Mac recover_mounts_if_needed: single remote command; no nested sshx on server' (($recoverLines | ForEach-Object { $_.Trim() }) -join ' || ')
    }
}

# --- 6) EditorSeenOpen cleared when editor not open ---
$pollClear = @(Select-String -LiteralPath $winConn -Pattern 'EDITOR_SEEN_CLEAR reason=editor_closed phase=session_poll' -SimpleMatch)
$assignClear = @(Select-String -LiteralPath $winConn -Pattern 'EditorSeenOpen = $false' -SimpleMatch)
$structOk = $connRaw -match '(?s)-not \$windowOpen[\s\S]{0,220}EditorSeenOpen = \$false'
if ($pollClear.Count -gt 0 -and $assignClear.Count -gt 0 -and $structOk) {
    Pass 'Win: EditorSeenOpen cleared when editor not open'
} else {
    Fail 'Win: EditorSeenOpen cleared when editor not open' "poll=$($pollClear.Count) assign=$($assignClear.Count) struct=$structOk"
}

Write-Host ''
Write-Host ("Contracts: $passes passed, $fail failed") -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
exit 0
