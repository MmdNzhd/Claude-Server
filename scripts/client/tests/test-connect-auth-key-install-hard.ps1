#Requires -Version 5.1
# test-connect-auth-key-install-hard.ps1
# HARD: the remote authorized_keys install behind CONNECT_AUTH_VERIFY.
#
# Regression guarded here: connect.ps1 used to push the pubkey with a bare
#   printf '%s\n' 'KEY' >> ~/.ssh/authorized_keys
# When the server's authorized_keys did not already end in a newline, that glued our key onto
# the previous entry - both lines became unparsable, sshd denied publickey, and the remote
# command STILL exited 0. Result in the daylog:
#   FAIL CONNECT_AUTH_VERIFY keyCopyOk=True verify_s=2.8 alias=claude-server ...
# Retrying only appended more glued lines, so the laptop could never recover on its own.
# mac/connect.sh never had the bug because it shells out to ssh-copy-id, which guards this.
#
# Static asserts always run. The LIVE section executes the EXACT command connect.ps1 emits
# against a throwaway HOME, and is skipped when no POSIX shell is present.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$c, [string]$m) {
    if ($c) { Write-Host "  PASS  $m" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:Fail++ }
}
function Skipped([string]$m) { Write-Host "  SKIP  $m" -ForegroundColor DarkYellow; $script:Skip++ }

Write-Host ''
Write-Host '=== HARD: CONNECT_AUTH_VERIFY key install ===' -ForegroundColor Cyan

$cp  = Get-ClientFile 'windows\connect.ps1'
$src = Get-Content -LiteralPath $cp -Raw

# Pull the real one-line command literal out of connect.ps1 so this test can never drift into
# asserting a re-implementation of it.
$m = [regex]::Match($src, "(?m)^\s*\`$installKeyCmd = '.*?'\s*$")
Assert $m.Success 'single-line $installKeyCmd literal found in connect.ps1'
if (-not $m.Success) { Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip); exit 1 }

$pubKeyContent = 'ssh-ed25519 AAAATESTKEYDATA smart@laptop'
Invoke-Expression $m.Value
$cmd = $installKeyCmd.Replace('__PUBKEY__', $pubKeyContent)

Write-Host ''
Write-Host '--- Static: emitted remote command ---' -ForegroundColor DarkCyan

Assert ($cmd -match 'tail -c1 ~/\.ssh/authorized_keys \| wc -l' -and $cmd -match 'echo >> ~/\.ssh/authorized_keys') `
    'newline guard present (append a newline when the file does not end in one)'
Assert ($cmd -match "grep -qxF '[^']+' ~/\.ssh/authorized_keys \|\| printf") `
    'idempotent: grep -qxF short-circuits the append on retry'
Assert ($cmd -match 'chmod go-w ~') `
    'drops group/other write on $HOME (sshd StrictModes)'
Assert ($cmd -match 'chmod 700 ~/\.ssh' -and $cmd -match 'chmod 600 ~/\.ssh/authorized_keys') `
    'keeps 700 ~/.ssh + 600 authorized_keys'
Assert ($cmd.TrimEnd() -match "grep -qxF '[^']+' ~/\.ssh/authorized_keys$") `
    'ends on grep -qxF so keyCopyOk proves the key line exists'
Assert ($cmd -notmatch '"') `
    'no double quotes (PS 5.1 native arg passing would mangle them before ssh sees them)'
Assert ($cmd -notmatch "`n") `
    'single line (a CRLF here-string would ship \r into the remote shell)'
Assert ($src -notmatch "chmod 700 ~/\.ssh && printf '%s\\n'") `
    'old unguarded append pattern gone from connect.ps1'

Write-Host ''
Write-Host '--- Static: identity pinning + failure reason ---' -ForegroundColor DarkCyan

Assert ($src -match '\$script:ConnectSshIdentityFile = \(\$keyA -replace') `
    'IdentityFile pinned to $keyA when .ssh is not the running profile'
Assert ($src -match 'if \(-not \$IdentityFile\) \{[\s\S]{0,200}?ConnectSshIdentityFile') `
    'Set-SshHostBlock resolves the pinned identity'
Assert ($src -match "\`$out\.Add\('    IdentitiesOnly yes'\)") `
    'alias block writes IdentitiesOnly yes (agent keys cannot burn MaxAuthTries)'
Assert ($src -match 'function Get-SshVerifyFailReason') `
    'Get-SshVerifyFailReason defined'
Assert ($src -match 'FAIL CONNECT_AUTH_VERIFY[^"]*reason=\{8\}') `
    'CONNECT_AUTH_VERIFY log carries reason='
Assert ($src -match '\$verifyReason = Get-SshVerifyFailReason -Alias \$Alias') `
    'failure path resolves the reason before logging'

# --- LIVE -------------------------------------------------------------------------------
function Get-PosixShell {
    foreach ($p in @(
        (Join-Path "$env:ProgramFiles" 'Git\bin\bash.exe'),
        (Join-Path "${env:ProgramFiles(x86)}" 'Git\bin\bash.exe'),
        (Join-Path "$env:LOCALAPPDATA" 'Programs\Git\bin\bash.exe')
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) { return @{ Kind = 'git'; Path = $p } }
    }
    # wsl.exe exists on stock Windows even with no distro installed - probe before trusting it.
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        $probe = (& wsl.exe -e sh -c 'echo POSIX_OK' 2>$null) -join ''
        if ($probe -match 'POSIX_OK') { return @{ Kind = 'wsl'; Path = 'wsl.exe' } }
    }
    return $null
}

function Invoke-PosixScript {
    param($Shell, [string]$Body)
    $tmp = Join-Path $env:TEMP ("cc-ak-{0}.sh" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    [IO.File]::WriteAllText($tmp, ($Body -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
    try {
        if ($Shell.Kind -eq 'git') { return @(& $Shell.Path ($tmp -replace '\\', '/') 2>&1) }
        $unix = (& wsl.exe wslpath -a ($tmp -replace '\\', '/') 2>$null) -join ''
        if (-not $unix) { return @() }
        return @(& wsl.exe bash $unix 2>&1)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host '--- LIVE: run the emitted command against a throwaway HOME ---' -ForegroundColor DarkCyan

$sh = Get-PosixShell
if (-not $sh) {
    Skipped 'no POSIX shell (Git bash / WSL) - LIVE section skipped'
} else {
    # Seed the exact hostile state: an existing key with NO trailing newline.
    $seed = "HOME=/tmp/cc-ak-live-`$`$`nexport HOME`nrm -rf `"`$HOME`"`nmkdir -p `"`$HOME/.ssh`"`ncd `"`$HOME`"`nprintf '%s' 'ssh-ed25519 AAAAOLDKEY old@host' > `"`$HOME/.ssh/authorized_keys`"`n"
    $tail = "echo LINES=`$(wc -l < `"`$HOME/.ssh/authorized_keys`")`necho PERM=`$(stat -c %a `"`$HOME/.ssh/authorized_keys`" 2>/dev/null)`ngrep -qxF 'ssh-ed25519 AAAAOLDKEY old@host' `"`$HOME/.ssh/authorized_keys`" && echo OLD_INTACT=1 || echo OLD_INTACT=0`ngrep -qxF '$pubKeyContent' `"`$HOME/.ssh/authorized_keys`" && echo NEW_OWN_LINE=1 || echo NEW_OWN_LINE=0`nrm -rf `"`$HOME`"`n"

    $out = @(Invoke-PosixScript -Shell $sh -Body ($seed + "$cmd`necho RC1=`$?`n" + "$cmd`necho RC2=`$?`n" + $tail))
    $txt = ($out -join "`n")

    Assert ($txt -match '(?m)^RC1=0')          'first install exits 0'
    Assert ($txt -match '(?m)^RC2=0')          'second install (retry) exits 0'
    Assert ($txt -match '(?m)^OLD_INTACT=1')   'pre-existing key survives on its own line'
    Assert ($txt -match '(?m)^NEW_OWN_LINE=1') 'our key lands on a line of its own'
    Assert ($txt -match '(?m)^LINES=2')        'idempotent: exactly 2 lines after two runs'
    Assert ($txt -match '(?m)^PERM=600')       'authorized_keys mode 600'

    # Contrast: the pre-fix command must actually corrupt the same seed, otherwise this whole
    # test would keep passing even if the guard were silently dropped again.
    $oldCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s\n' '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    $oldOut = @(Invoke-PosixScript -Shell $sh -Body ($seed + "$oldCmd`necho RC=`$?`n" + $tail))
    $oldTxt = ($oldOut -join "`n")
    Assert ($oldTxt -match '(?m)^RC=0' -and $oldTxt -match '(?m)^LINES=1' -and $oldTxt -match '(?m)^OLD_INTACT=0') `
        'pre-fix command still reproduces the bug (exit 0, both keys glued into 1 line)'
}

Write-Host ''
if ($Fail -eq 0) { Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green; exit 0 }
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red; exit 1
