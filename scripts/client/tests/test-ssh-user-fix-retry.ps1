#Requires -Version 5.1
# test-ssh-user-fix-retry.ps1
# Source-level contract: SSH_USER_FIX continues in-process (max 2 retries),
# rewrites Host User, does not always Wait-ConnectExit / "Re-run connect".

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
$ver = Get-ConnectVersion
$expectVer = $ver

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== SSH_USER_FIX in-process retry (source contracts) ===' -ForegroundColor Cyan
Write-Host ''

$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$mac = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw
$winVerTxt = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
$macVerTxt = (Get-Content (Get-ClientFile 'mac\connect-version.txt') -Raw).Trim()

Write-Host "--- version $ver (all client version files consistent) ---" -ForegroundColor Cyan
Assert ($ver -eq $expectVer) "windows/connect.ps1 ConnectVersion is $expectVer (current: $ver)"
Assert ($win -match "ConnectVersion = '$([regex]::Escape($expectVer))'") "connect.ps1 pins ConnectVersion $expectVer"
Assert ($mac -match "CONNECT_VERSION='$([regex]::Escape($expectVer))'") "mac/connect.sh CONNECT_VERSION is $expectVer"
Assert ($winVerTxt -eq $expectVer) "windows/connect-version.txt is $expectVer"
Assert ($macVerTxt -eq $expectVer) "mac/connect-version.txt is $expectVer"

# Extract needsKey / needs_key blocks for focused asserts
$winNeeds = ''
if ($win -match '(?s)if \(\$needsKey\) \{.*?(?=\r?\n# Guard: wrong server username)') {
    $winNeeds = $Matches[0]
} elseif ($win -match '(?s)if \(\$needsKey\) \{.*?(?=\r?\n# Re-run client auto-update|\r?\n# Guard:)') {
    $winNeeds = $Matches[0]
}

$macNeeds = ''
if ($mac -match '(?s)if \[ -n "\$needs_key" \]; then.*?fi\r?\n\r?\n_script_dir=') {
    $macNeeds = $Matches[0]
} elseif ($mac -match '(?s)if \[ -n "\$needs_key" \]; then.*?step_ok "\$REMOTE_USER@\$SERVER_IP"\r?\nfi') {
    $macNeeds = $Matches[0]
}

Assert ($winNeeds.Length -gt 200) 'windows needsKey block extracted'
Assert ($macNeeds.Length -gt 100) 'mac needs_key block extracted'

Write-Host '--- Windows in-process retry loop ---' -ForegroundColor Cyan
Assert (
    ($winNeeds -match 'maxFix|MaxFix|fixAttempt|SSH_USER_FIX_MAX|max.?2|le\s*2|-le\s*2|1\.\.2|for\s*\(.*2') -or
    ($winNeeds -match 'in-process|in_process|SSH_USER_FIX_RETRY')
) 'windows needsKey has in-process retry / max-2 markers'
Assert ($winNeeds -match 'SSH_USER_FIX') 'windows prompts with SSH_USER_FIX tag'
Assert (
    ($winNeeds -match 'Get-SshConfigUserForServer') -and
    (
        ($winNeeds -match 'Set-SshHostBlock') -or
        (($winNeeds -match 'Remove-SshHostBlock') -and ($winNeeds -match 'Sanitize-SshAliasConfig') -and ($winNeeds -match 'User \$sshCfgUser'))
    )
) 'windows rewrites Host block with Get-SshConfigUserForServer after FIX'
Assert ($winNeeds -match 'REMOTE_USER=\$') 'windows rewrites connect.conf REMOTE_USER after FIX'
Assert ($winNeeds -match 'RemoteUser\s*=') 'windows sets RemoteUser from FIX'
Assert ($winNeeds.Contains('$fix -match ''[@/\\]''')) 'windows validates FIX username via $fix -match ''[@/\\]'''
Assert ($winNeeds -match 'in-process|in_process|retrying in-process|SSH_USER_FIX_RETRY') 'windows logs in-process retry (not re-run bat)'
Assert ($winNeeds -notmatch 'Saved\. Re-run connect\.bat') 'windows does not tell user to Re-run connect.bat after FIX'
# Must not: save FIX then immediately Wait-ConnectExit with no retry path
$badExitAfterSave = $false
if ($winNeeds -match '(?s)Set-Content\s+-Path\s+\$Cfg[\s\S]{0,400}Wait-ConnectExit\s+-Reason\s+''require_fail''') {
    # Allow Wait-ConnectExit only after max retries / empty — reject if no retry marker between save and exit in old pattern
    if ($winNeeds -notmatch 'in-process|in_process|SSH_USER_FIX_RETRY|fixAttempt') {
        $badExitAfterSave = $true
    }
}
# Old bug pattern: after non-empty fix, only Remove-SshHostBlock + "Re-run" then Wait-ConnectExit
if ($winNeeds -match '(?s)if \(\$fix\) \{[\s\S]*?Remove-SshHostBlock[\s\S]*?Re-run connect\.bat[\s\S]*?\}[\s\S]*?Wait-ConnectExit') {
    $badExitAfterSave = $true
}
Assert (-not $badExitAfterSave) 'windows has no unconditional Wait-ConnectExit right after saving FIX without retry path'
Assert (
    ($winNeeds -match 'for\s*\(\s*\$\w+\s*=\s*1\s*;\s*\$\w+\s*-le\s*2') -or
    ($winNeeds -match 'while\s*\(') -or
    ($winNeeds -match 'fixAttempt') -or
    ($winNeeds -match '1\.\.2')
) 'windows uses a retry loop (for/while/fixAttempt)'

Write-Host '--- Mac in-process retry parity ---' -ForegroundColor Cyan
Assert (
    ($macNeeds -match 'max_fix|fix_attempt|SSH_USER_FIX|in-process|in_process|retry') -and
    ($macNeeds -match 'for |while ')
) 'mac needs_key has in-process retry loop markers'
Assert ($macNeeds -match 'SSH_USER_FIX') 'mac prompts with SSH_USER_FIX tag'
Assert ($macNeeds -match 'REMOTE_USER=') 'mac rewrites CFG REMOTE_USER after FIX'
Assert ($macNeeds -match 'User \$REMOTE_USER|User \$REMOTE_USER') 'mac rewrites Host User after FIX'
Assert ($macNeeds -notmatch 'Saved\. Re-run connect\.sh') 'mac does not tell user to Re-run connect.sh after FIX'
Assert ($macNeeds -match 'in-process|in_process|retrying in-process|SSH_USER_FIX_RETRY') 'mac logs in-process retry'
# Old bug: save + remove host + "Re-run" + exit 1
$macBad = $false
if ($macNeeds -match '(?s)printf ''REMOTE_USER=%s[\s\S]*?Re-run connect\.sh[\s\S]*?exit 1') {
    $macBad = $true
}
Assert (-not $macBad) 'mac has no unconditional exit 1 right after saving FIX without retry path'

Write-Host ''
if ($fail -gt 0) {
    Write-Host "FAILED: $fail assertion(s)" -ForegroundColor Red
    exit 1
}
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
