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
    # Escape for embedding inside a single-quoted bash assignment (avoid double quotes).
    $lu = ($LaptopUser -replace "'", "'\''")
    $modeEsc = ($mode -replace "'", "'\''")
    $preferEsc = ($preferAm -replace "'", "'\''")
    $portEsc = ("$Port" -replace "'", "'\''")
    Write-GitModeLog "PUSH_CONF begin laptop_user=$LaptopUser port=$Port git_mode=$mode prefer_mount=$preferAm clear=$ClearActiveMount" 'INFO'
    # Windows OpenSSH eats nested double quotes in remote payloads (AM="" -> AM="; elif syntax error).
    # Ship remote body as base64 so ACTIVE_MOUNT always lands correctly and stays trackable.
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
