$ErrorActionPreference = 'Continue'
$repo = (Get-Location).Path
$outDir = Join-Path $repo 'scripts\tmp'
$logRoot = Join-Path $outDir 'agent-l-hard-logs'
New-Item -ItemType Directory -Force -Path $outDir,$logRoot | Out-Null
$results = New-Object System.Collections.Generic.List[object]

function Invoke-TimedTest {
    param([string]$Name, [string]$FileArgs, [int]$TimeoutSec = 120, [string]$Exe = 'powershell')
    $log = Join-Path $logRoot ($Name + '.log')
    Write-Host ""
    Write-Host "===== RUN $Name (timeout=${TimeoutSec}s) =====" -ForegroundColor Cyan
    if (Test-Path $log) { Remove-Item $log -Force }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($Exe -eq 'powershell') {
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File $FileArgs"
    } elseif ($Exe -eq 'bash') {
        $psi.FileName = $FileArgs.Split('|')[0]
        $psi.Arguments = $FileArgs.Substring($psi.FileName.Length+1)
    } else {
        $psi.FileName = $Exe
        $psi.Arguments = $FileArgs
    }
    $psi.WorkingDirectory = $repo
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        $sw.Stop()
        $tail = "TIMEOUT after ${TimeoutSec}s"
        [IO.File]::WriteAllText($log, $tail)
        $entry = [pscustomobject]@{ Name=$Name; ExitCode=124; Seconds=[math]::Round($sw.Elapsed.TotalSeconds,1); Tail=$tail; Pass=$false }
        $results.Add($entry)
        Write-Host "===== EXIT $Name rc=124 TIMEOUT =====" -ForegroundColor Red
        return
    }
    $sw.Stop()
    $stdout = $outTask.Result
    $stderr = $errTask.Result
    $all = $stdout + "`n" + $stderr
    [IO.File]::WriteAllText($log, $all)
    $rc = $p.ExitCode
    $tailLines = ($all -split "`r?`n" | Where-Object { $_ -ne '' } | Select-Object -Last 15) -join "`n"
    $entry = [pscustomobject]@{ Name=$Name; ExitCode=$rc; Seconds=[math]::Round($sw.Elapsed.TotalSeconds,1); Tail=$tailLines; Pass=($rc -eq 0) }
    $results.Add($entry)
    Write-Host ("===== EXIT {0} rc={1} ({2}s) =====" -f $Name,$rc,$entry.Seconds) -ForegroundColor $(if($rc -eq 0){'Green'}else{'Red'})
}

Invoke-TimedTest 'test-connect-update-quick' (Join-Path $repo 'scripts\client\tests\test-connect-update-quick.ps1') 90
Invoke-TimedTest 'test-connect-update-e2e' (Join-Path $repo 'scripts\client\tests\test-connect-update-e2e.ps1') 90
Invoke-TimedTest 'test-connect-update-desktop' (Join-Path $repo 'scripts\client\tests\test-connect-update-desktop.ps1') 60
Invoke-TimedTest 'test-publish' (Join-Path $repo 'scripts\client\tests\test-publish.ps1') 120

$bash = $null
foreach ($c in @('C:\Program Files\Git\bin\bash.exe','C:\Program Files\Git\usr\bin\bash.exe')) {
    if (Test-Path $c) { $bash = $c; break }
}
if ($bash) {
    $repoUnix = ($repo -replace '\\','/')
    if ($repoUnix -match '^[A-Za-z]:') { $repoUnix = '/' + $repoUnix.Substring(0,1).ToLower() + $repoUnix.Substring(2) }
    $cmd = "-lc `"cd '$repoUnix' && bash scripts/client/tests/test-client-auto-update.sh`""
    Invoke-TimedTest 'test-client-auto-update' "$bash|$cmd" 90 'bash'
} else {
    $results.Add([pscustomobject]@{Name='test-client-auto-update';ExitCode=1;Seconds=0;Tail='Git bash not found';Pass=$false})
}

Invoke-TimedTest 'test-update-exit-contract' (Join-Path $repo 'scripts\tmp\test-update-exit-contract.ps1') 60

# Static verifies against live sources
Write-Host ""
Write-Host '===== STATIC VERIFIES =====' -ForegroundColor Cyan
$ps1 = Join-Path $repo 'scripts\client\windows\connect-update.ps1'
$sh  = Join-Path $repo 'scripts\client\mac\connect-update.sh'
$bat = Join-Path $repo 'scripts\client\windows\connect.bat'
$ps1Raw = Get-Content $ps1 -Raw
$shRaw  = Get-Content $sh -Raw
$batRaw = Get-Content $bat -Raw
$auto = Get-Content (Join-Path $repo 'scripts\client\tests\test-client-auto-update.sh') -Raw

$csCode = ($ps1Raw -match 'Test-BundleChecksums') -and ($ps1Raw -match 'Get-FileHash') -and ($shRaw -match '_verify_checksums')
$csTested = ($auto -match 'Test-BundleChecksums\|checksums\.txt' -or $auto -match 'checksum')
$checksumOk = $csCode -and $csTested
$results.Add([pscustomobject]@{Name='verify-checksum';ExitCode=$(if($checksumOk){0}else{1});Seconds=0;Tail=("code={0} tested={1}" -f $csCode,$csTested);Pass=$checksumOk})

$rbPs = ($ps1Raw -match 'Restore-FromBak|apply_rollback|Swap-LiveDir')
$rbSh = ($shRaw -match 'apply_rollback|rolled back')
$rollbackOk = $rbPs -and $rbSh
$results.Add([pscustomobject]@{Name='verify-rollback-partial';ExitCode=$(if($rollbackOk){0}else{1});Seconds=0;Tail=("ps={0} sh={1}" -f $rbPs,$rbSh);Pass=$rollbackOk})

$relaunchBound = ($batRaw -match 'CLAUDE_CONNECT_UPDATE_DEPTH') -and ($batRaw -match 'GEQ 3') -and ($batRaw -match 'call "%~f0"')
$results.Add([pscustomobject]@{Name='verify-bat-relaunch-bound';ExitCode=$(if($relaunchBound){0}else{1});Seconds=0;Tail=("depthGuard={0}" -f $relaunchBound);Pass=$relaunchBound})

$overallFail = @($results | Where-Object { -not $_.Pass }).Count -gt 0
$overall = if ($overallFail) { 'HARD FAIL' } else { 'HARD PASS' }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Agent L — HARD update matrix (wave2)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(("Date: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
[void]$sb.AppendLine('Project: `-p claude-code-server` (laptop-exec only; no live deploy/publish)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(("## Overall: **{0}**" -f $overall))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Test | Exit | Result | Seconds | Tail (truncated) |')
[void]$sb.AppendLine('|------|------|--------|---------|----------------|')
foreach ($r in $results) {
    $note = ($r.Tail -replace '\r?\n', ' / ' -replace '\|','/')
    if ($note.Length -gt 140) { $note = $note.Substring(0,137) + '...' }
    [void]$sb.AppendLine(("| `{0}` | {1} | {2} | {3} | {4} |" -f $r.Name,$r.ExitCode,$(if($r.Pass){'PASS'}else{'FAIL'}),$r.Seconds,$note))
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Per-test tails')
[void]$sb.AppendLine('')
foreach ($r in $results) {
    [void]$sb.AppendLine(("### {0} (exit={1}, {2})" -f $r.Name,$r.ExitCode,$(if($r.Pass){'PASS'}else{'FAIL'})))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine($(if($r.Tail){$r.Tail}else{'(empty)'}))
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine('')
}
[void]$sb.AppendLine('## Verify notes')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- Checksum: `Test-BundleChecksums` / `_verify_checksums` + `checksums.txt`; covered by `test-client-auto-update.sh` grep contract.')
[void]$sb.AppendLine('- Rollback: Windows `Restore-FromBak` / `Swap-LiveDir` + `apply_rollback`; Mac `apply_rollback` after failed swap.')
[void]$sb.AppendLine('- Relaunch bound: `CLAUDE_CONNECT_UPDATE_DEPTH` with `GEQ 3` stop in `connect.bat`.')
[void]$sb.AppendLine('- ERROR exit contract: `scripts/tmp/test-update-exit-contract.ps1` (Select-String).')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(("**Verdict: {0}**" -f $overall))
$md = Join-Path $outDir 'TEST-AGENT-UPDATE-HARD.md'
[IO.File]::WriteAllText($md, $sb.ToString(), [Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "Wrote $md"
Write-Host "OVERALL $overall" -ForegroundColor $(if($overallFail){'Red'}else{'Green'})
if ($overallFail) { exit 1 } else { exit 0 }
