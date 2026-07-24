# test-sshx-hard-kill.ps1 - #P3 Invoke-SshXCore must hard-kill on client wall-clock cap,
# because ServerAliveInterval/CountMax only catch a dead *transport*, not a hung remote
# pty/session that keeps the link technically alive (observed: probes hung 6+ hours).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function Get-FunctionSource {
    param([string]$Content, [string]$Name)
    $m = [regex]::Match($Content, "function\s+$Name\b")
    if (-not $m.Success) { return $null }
    $start = $m.Index
    $i = $Content.IndexOf('{', $start)
    $depth = 0
    for ($j = $i; $j -lt $Content.Length; $j++) {
        if ($Content[$j] -eq '{') { $depth++ }
        elseif ($Content[$j] -eq '}') { $depth--; if ($depth -eq 0) { return $Content.Substring($start, $j - $start + 1) } }
    }
    return $null
}

Write-Host ''
Write-Host '=== SSH client hard-kill #P3 (static) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$core = Get-FunctionSource -Content $content -Name 'Invoke-SshXCore'
Assert ($core -ne $null -and $core.Length -gt 50) 'Invoke-SshXCore extracted'

if ($core) {
    Assert ($core -match 'Start-Process\s+-FilePath\s+.ssh.') 'uses Start-Process (not blocking native-exe call) so it can be killed'
    Assert ($core -match '\$script:SshXCoreHardKillMs') 'has a configurable client-side hard-kill ceiling'
    Assert ($core -match 'WaitForExit\(\s*\[int\]\$script:SshXCoreHardKillMs\s*\)') 'WaitForExit is bounded by the hard-kill ceiling, not unbounded'
    Assert ($core -match '\$proc\.Kill\(\)') 'kills the process when the wait times out'
    Assert ($core -match '\$exitCode\s*=\s*124') 'timeout path reports exit=124 (same sentinel as remote timeout, compatible with existing retry/log logic)'
    Assert ($core -match '\$null\s*=\s*\$proc\.Handle') 'touches .Handle before WaitForExit (avoids PS5.1 ExitCode-null quirk on Start-Process -PassThru)'
    Assert ($core -match 'RedirectStandardOutput') 'redirects stdout to a file (still captures Out/Lines for callers)'
    Assert ($core -match 'RedirectStandardError') 'redirects stderr to a file (still captures Out/Lines for callers)'
    Assert ($core -match 'Remove-Item\s+-LiteralPath\s+\$stdoutPath,\s*\$stderrPath') 'cleans up its own temp files'
    # Existing CRLF-stripping contract (test-ssh-remote-bash-lf-only.ps1) must still hold.
    Assert ($core -match 'replace\s+"`r`n"|replace\s+''`r`n''|-replace\s+"`r`n"') 'still strips CRLF (pre-existing contract preserved)'
    Assert ($core -match '-replace\s+"`r"') 'still strips lone CR (pre-existing contract preserved)'
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
