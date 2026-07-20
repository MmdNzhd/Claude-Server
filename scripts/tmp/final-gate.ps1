#Requires -Version 5.1
# Independent final gate - HARD FAIL unless all checks pass. No deploy.
$ErrorActionPreference = 'Continue'
$Here = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path (Get-Location) 'scripts/tmp' }
$Root = (Get-Location).Path
if (-not (Test-Path (Join-Path $Root 'scripts/client/windows/connect.ps1'))) {
    $cand = Split-Path (Split-Path $Here -Parent) -Parent
    if (Test-Path (Join-Path $cand 'scripts/client/windows/connect.ps1')) { $Root = $cand }
}
$Client = Join-Path $Root 'scripts/client'
$ConnectPs1 = Join-Path $Client 'windows/connect.ps1'
$GitModeSh = Join-Path $Client 'git-mode.sh'
$GitModePs1 = Join-Path $Client 'git-mode.ps1'
$TestConnect = Join-Path $Client 'tests/test-connect-pipeline.ps1'
$TestGitDeep = Join-Path $Client 'tests/test-git-mode-deep.ps1'
$OutMd = Join-Path $Here 'FINAL-GATE.md'

$results = New-Object System.Collections.Generic.List[object]
$failed = 0

function Add-Result([string]$Name, [bool]$Pass, [string]$Evidence) {
    $script:results.Add([pscustomobject]@{ Name = $Name; Pass = $Pass; Evidence = $Evidence })
    if (-not $Pass) { $script:failed++ }
    $tag = 'FAIL'
    if ($Pass) { $tag = 'PASS' }
    Write-Host "[$tag] $Name"
    Write-Host "  $Evidence"
}

function Get-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $false))
}

function Get-RecoverMountsBody([string]$Text) {
    $lines = $Text -split "`r?`n"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^recover_mounts') { $start = $i; break }
    }
    if ($start -lt 0) { return '' }
    $depth = 0
    $buf = New-Object System.Collections.Generic.List[string]
    for ($i = $start; $i -lt $lines.Count; $i++) {
        [void]$buf.Add($lines[$i])
        $depth += ([regex]::Matches($lines[$i], '\{')).Count
        $depth -= ([regex]::Matches($lines[$i], '\}')).Count
        if ($i -gt $start -and $depth -le 0) { break }
    }
    return ($buf -join "`n")
}

# --- 1 ---
$cText = Get-Text $ConnectPs1
$curly = [regex]::Matches($cText, "[\u201C\u201D\u2018\u2019]")
Add-Result '1.connect.ps1 no curly quotes' ($curly.Count -eq 0) ("matches=$($curly.Count) file=$ConnectPs1")

# --- 2 ---
$sh = Get-Text $GitModeSh
$seq12 = [regex]::Matches($sh, 'seq\s+1\s+12')
$seq14 = [regex]::Matches($sh, 'seq\s+1\s+4\b')
$waitHits = New-Object System.Collections.Generic.List[string]
$lines = $sh -split "`r?`n"
$inWait = $false
$waitName = ''
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\)\s*\{') {
        if ($Matches[1] -match 'wait') {
            $inWait = $true
            $waitName = $Matches[1]
        }
    }
    if ($inWait -and $lines[$i] -match 'seq\s+1\s+12') {
        [void]$waitHits.Add("$waitName`:L$($i+1)")
    }
    if ($inWait -and $lines[$i] -match '^\}') { $inWait = $false }
}
$ok2 = ($seq12.Count -eq 2) -and ($seq14.Count -eq 0)
Add-Result '2.git-mode.sh seq 1 12 x2 in wait fns; zero seq 1 4' $ok2 ("seq_1_12=$($seq12.Count) seq_1_4=$($seq14.Count) wait_hits=[$($waitHits -join '; ')]")

# --- 3 ---
$recoverFn = Get-RecoverMountsBody $sh
$goodLine = [regex]::Matches($recoverFn, 'sshx\s+"timeout\s+30\s+\$CM\s+recover-one[^"]*"')
$badNested = [regex]::IsMatch($recoverFn, 'timeout\s+30\s+sshx\s+"\$CM') -or [regex]::IsMatch($sh, 'timeout\s+30\s+sshx\s+"\$CM')
$recoverOneSshx = ([regex]::Matches($recoverFn, 'sshx\s+"[^"]*recover-one[^"]*"')).Count
$ok3 = ($goodLine.Count -eq 1) -and (-not $badNested) -and ($recoverOneSshx -eq 1) -and ($recoverFn.Length -gt 0)
Add-Result '3.recover_mounts single sshx remote timeout 30 $CM recover-one' $ok3 ("good_sshx_timeout30_recover-one=$($goodLine.Count) bad_timeout30_sshx_CM=$badNested recover-one_sshx_count=$recoverOneSshx fn_len=$($recoverFn.Length)")

# --- 4 ---
$ps1 = Get-Text $GitModePs1
$hasBanner = $ps1.Contains('banner_miss_tcp_open_budget')
$hasReseed = $ps1.Contains('action=reseed')
$ok4 = $hasBanner -and $hasReseed
Add-Result '4.git-mode.ps1 banner_miss_tcp_open_budget AND action=reseed' $ok4 ("banner_miss_tcp_open_budget=$hasBanner action=reseed=$hasReseed")

# --- 5 ---
$out5 = & powershell -NoProfile -File $TestConnect 2>&1 | Out-String
$exit5 = $LASTEXITCODE
if ($null -eq $exit5) { $exit5 = 0 }
$tail5 = (($out5 -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 8) -join ' / ')
Add-Result '5.test-connect-pipeline.ps1 exit 0' ($exit5 -eq 0) ("exit=$exit5 / $tail5")

# --- 6 ---
$out6 = & powershell -NoProfile -File $TestGitDeep 2>&1 | Out-String
$exit6 = $LASTEXITCODE
if ($null -eq $exit6) { $exit6 = 0 }
$tail6 = (($out6 -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 8) -join ' / ')
Add-Result '6.test-git-mode-deep.ps1 exit 0' ($exit6 -eq 0) ("exit=$exit6 / $tail6")

$overall = 'FAIL'
if ($failed -eq 0) { $overall = 'PASS' }
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# FINAL-GATE')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("**OVERALL: $overall**")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("- Generated: $((Get-Date).ToString('o'))")
[void]$sb.AppendLine("- Root: $Root")
[void]$sb.AppendLine("- Failed: $failed / $($results.Count)")
[void]$sb.AppendLine('- Agent: independent verify; laptop-exec -p claude-code-server; no deploy')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Check | Result | Evidence |')
[void]$sb.AppendLine('|-------|--------|----------|')
foreach ($r in $results) {
    $tag = 'FAIL'
    if ($r.Pass) { $tag = 'PASS' }
    $ev = ($r.Evidence -replace '\|', '/' -replace '`', "'" -replace "`r?`n", ' ')
    [void]$sb.AppendLine("| $($r.Name) | **$tag** | $ev |")
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Verdict')
$exitNote = '1'
if ($failed -eq 0) { $exitNote = '0' }
[void]$sb.AppendLine("OVERALL **$overall** - gate exit $exitNote.")
[System.IO.File]::WriteAllText($OutMd, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "OVERALL: $overall (wrote $OutMd)"
if ($failed -gt 0) { exit 1 } else { exit 0 }
