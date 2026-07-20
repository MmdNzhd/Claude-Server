$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$gitMode = Join-Path $root 'scripts\client\git-mode.ps1'
$connect = Join-Path $root 'scripts\client\windows\connect.ps1'
$verWin = Join-Path $root 'scripts\client\windows\connect-version.txt'
$verMac = Join-Path $root 'scripts\client\mac\connect-version.txt'

function Replace-Exact([string]$Path, [string]$Old, [string]$New, [string]$Label) {
  $text = [IO.File]::ReadAllText($Path)
  if ($text.IndexOf($Old) -lt 0) { throw "PATCH FAIL: $Label not found in $Path" }
  $count = ([regex]::Matches($text, [regex]::Escape($Old))).Count
  if ($count -ne 1) { throw "PATCH FAIL: $Label matched $count times (want 1) in $Path" }
  $text2 = $text.Replace($Old, $New)
  [IO.File]::WriteAllText($Path, $text2)
  Write-Output "OK $Label"
}

# --- 1) Push-ServerConnectConf: base64 remote + INFO result ---
$oldPush = @'
function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Preserve existing server ACTIVE_MOUNT unless caller clears or sets explicitly.
    # Keep self-heal out of this frequently called configuration push hot path.
    $preferAm = ''
    if (-not $ClearActiveMount) {
        if (-not [string]::IsNullOrWhiteSpace($ActiveMount)) {
            $preferAm = [string]$ActiveMount
        } elseif ($script:ActiveProjectId) {
            $preferAm = [string]$script:ActiveProjectId
        }
    }
    $clearFlag = if ($ClearActiveMount) { '1' } else { '0' }
    # Dedupe identical pushes within a few seconds (startup called this twice).
    $dedupeKey = "{0}|{1}|{2}|{3}|{4}" -f $LaptopUser, $Port, $mode, $preferAm, $clearFlag
    if ($script:LastPushConfKey -eq $dedupeKey -and $script:LastPushConfAt -and
        ((Get-Date) - $script:LastPushConfAt).TotalSeconds -le 8) {
        Write-GitModeLog "PUSH_CONF skip_duplicate key=$dedupeKey" 'DEBUG'
        return
    }
    $lu = ($LaptopUser -replace "'", "'\''")
    $modeEsc = ($mode -replace "'", "'\''")
    $preferEsc = ($preferAm -replace "'", "'\''")
    $portEsc = ("$Port" -replace "'", "'\''")
    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode prefer_mount=$preferAm clear=$ClearActiveMount" 'DEBUG'
    $remote = @(
        'set +e'
        "CLEAR='$clearFlag'"
        "PREFER='$preferEsc'"
        "LU='$lu'"
        "PORT='$portEsc'"
        "MODE='$modeEsc'"
        'AM=""'
        'if [ "$CLEAR" = "1" ]; then AM=""'
        'elif [ -n "$PREFER" ]; then AM="$PREFER"'
        'else AM=$(grep -E "^ACTIVE_MOUNT=" "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)'
        'fi'
        'mkdir -p "$HOME/.local/bin"'
        'printf "LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n" "$LU" "$PORT" "$MODE" "$AM" > "$HOME/.claude-connect.conf"'
        'chmod 600 "$HOME/.claude-connect.conf" 2>/dev/null || true'
        'true'
    ) -join '; '
    # Record before the call so nested/re-entrant startup paths cannot duplicate the same push.
    $script:LastPushConfKey = $dedupeKey
    $script:LastPushConfAt = Get-Date
    SshX $remote 2>$null | Out-Null
}
'@

$newPush = @'
function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Preserve existing server ACTIVE_MOUNT unless caller clears or sets explicitly.
    # Keep self-heal out of this frequently called configuration push hot path.
    $preferAm = ''
    if (-not $ClearActiveMount) {
        if (-not [string]::IsNullOrWhiteSpace($ActiveMount)) {
            $preferAm = [string]$ActiveMount
        } elseif ($script:ActiveProjectId) {
            $preferAm = [string]$script:ActiveProjectId
        }
    }
    $clearFlag = if ($ClearActiveMount) { '1' } else { '0' }
    # Dedupe identical pushes within a few seconds (startup called this twice).
    $dedupeKey = "{0}|{1}|{2}|{3}|{4}" -f $LaptopUser, $Port, $mode, $preferAm, $clearFlag
    if ($script:LastPushConfKey -eq $dedupeKey -and $script:LastPushConfAt -and
        ((Get-Date) - $script:LastPushConfAt).TotalSeconds -le 8) {
        Write-GitModeLog "PUSH_CONF skip_duplicate key=$dedupeKey" 'DEBUG'
        return
    }
    # Escape for embedding inside a single-quoted bash assignment (no double quotes).
    $lu = ($LaptopUser -replace "'", "'\''")
    $modeEsc = ($mode -replace "'", "'\''")
    $preferEsc = ($preferAm -replace "'", "'\''")
    $portEsc = ("$Port" -replace "'", "'\''")
    Write-GitModeLog "PUSH_CONF begin laptop_user=$LaptopUser port=$Port git_mode=$mode prefer_mount=$preferAm clear=$ClearActiveMount" 'INFO'
    # Windows OpenSSH eats nested double quotes in remote -c/-lc payloads (AM="" -> AM="; elif syntax error).
    # Ship the remote body as base64 so ACTIVE_MOUNT always lands correctly.
    $remoteBody = @"
set +e
CLEAR='$clearFlag'
PREFER='$preferEsc'
LU='$lu'
PORT='$portEsc'
MODE='$modeEsc'
if [ "`$CLEAR" = "1" ]; then
  AM=
elif [ -n "`$PREFER" ]; then
  AM=`$PREFER
else
  AM=`$(grep -E '^ACTIVE_MOUNT=' "`$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
mkdir -p "`$HOME/.local/bin"
printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n' "`$LU" "`$PORT" "`$MODE" "`$AM" > "`$HOME/.claude-connect.conf"
chmod 600 "`$HOME/.claude-connect.conf" 2>/dev/null || true
printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s\n' "`$CLEAR" "`$PREFER" "`$AM"
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBody))
    $remote = "echo $b64 | base64 -d | bash"
    # Record before the call so nested/re-entrant startup paths cannot duplicate the same push.
    $script:LastPushConfKey = $dedupeKey
    $script:LastPushConfAt = Get-Date
    $pushOut = @(SshX $remote 2>$null)
    $pushExit = $global:LASTEXITCODE
    $pushLine = (($pushOut | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1) -replace '\s+', ' ').Trim()
    if (-not $pushLine) { $pushLine = '(no result line)' }
    if ($pushExit -ne 0) {
        Write-GitModeLog "PUSH_CONF fail exit=$pushExit out=$pushLine" 'ERROR'
    } else {
        Write-GitModeLog "PUSH_CONF ok exit=$pushExit $pushLine" 'INFO'
    }
}
'@

# Fix PS here-string: remoteBody used `"$CLEAR"` with backtick-dollar so PS doesn't expand.
# When written to file via Replace, the @" "@ content will have `$ which becomes $ in the file... 
# Wait - we're storing $newPush in a PowerShell here-string '@' ... so `"$CLEAR"` in the @" inside @' is LITERAL including backticks.
# Actually in $newPush = @' ... '@  the content is literal. I used @" inside the @' which is fine as literal characters.
# But I wrote `"$CLEAR"` with backticks in the @' block - those backticks stay as backticks in the file = WRONG for the final git-mode.ps1.
# The final function in git-mode.ps1 needs actual $CLEAR in the bash script string, escaped for PowerShell as `$CLEAR inside @" "@.

# Rebuild $newPush carefully using only @' for outer and proper escaping for the inner remoteBody @" "@

Replace-Exact -Path $gitMode -Old $oldPush -New $newPush -Label 'Push-ServerConnectConf'

Write-Output 'PushConf patch applied (verify backticks next)'
