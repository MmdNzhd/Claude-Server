#Requires -Version 5.1
# test-mac-connect-hard-batch.ps1
# Hard static contracts: Mac connect parity vs Windows client invariants (CLAUDE.md).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
$assertCount = 0
$ver = Get-ConnectVersion

function Assert([bool]$Cond, [string]$Msg) {
    $script:assertCount++
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Mac connect hard batch (Windows parity invariants) ===' -ForegroundColor Cyan
Write-Host ''

$macPath = Get-ClientFile 'mac\connect.sh'
$macUpdatePath = Get-ClientFile 'mac\connect-update.sh'
$gitModePath = Get-ClientFile 'git-mode.sh'
$uiPath = Get-ClientFile 'connect-ui.sh'

$mac = Get-Content -LiteralPath $macPath -Raw
$macUpdate = if (Test-Path -LiteralPath $macUpdatePath) { Get-Content -LiteralPath $macUpdatePath -Raw } else { '' }
$gitMode = Get-Content -LiteralPath $gitModePath -Raw
$ui = if (Test-Path -LiteralPath $uiPath) { Get-Content -LiteralPath $uiPath -Raw } else { '' }

$winVerTxt = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
$macVerTxt = (Get-Content (Get-ClientFile 'mac\connect-version.txt') -Raw).Trim()

# 1) bash -n syntax (mac/connect.sh)
$bash = 'C:\Program Files\Git\bin\bash.exe'
$bashOk = $true
if (Test-Path -LiteralPath $bash) {
    & $bash -n $macPath
    if ($LASTEXITCODE -ne 0) { $bashOk = $false }
} else {
    # Git Bash absent: still require balanced braces as a cheap static fallback
    $open = ([regex]::Matches($mac, '\{')).Count
    $close = ([regex]::Matches($mac, '\}')).Count
    $bashOk = ($open -eq $close)
}
Assert $bashOk 'mac/connect.sh passes bash -n (or balanced-brace fallback when bash missing)'

# 2) CONNECT_VERSION lockstep: connect.sh + both version.txt files
Assert (
    ($mac -match "CONNECT_VERSION='$([regex]::Escape($ver))'") -and
    ($winVerTxt -eq $ver) -and ($macVerTxt -eq $ver) -and ($winVerTxt -eq $macVerTxt)
) "CONNECT_VERSION lockstep connect.sh + version.txt ($ver)"

# 3) connect-update.sh copies windows connect-version.txt into mac/ on apply
Assert (
    ($macUpdate -match 'NEW_ROOT/windows/connect-version\.txt') -and
    ($macUpdate -match 'cp -f "\$NEW_ROOT/windows/connect-version\.txt" "\$NEW_ROOT/mac/connect-version\.txt"')
) 'connect-update.sh syncs mac/connect-version.txt from windows on update'

# 4) CONNECT_PORT_BASE=20000 (non-overlapping port block base)
Assert ($mac -match '(?m)^CONNECT_PORT_BASE=20000\b') 'mac/connect.sh sets CONNECT_PORT_BASE=20000'

# 5) tunnel_port_user_base: 20000 + (UID - 1000) * 10
$tunnelBaseFn = [regex]::Match($gitMode, '(?ms)^tunnel_port_user_base\(\)\s*\{.*?(?=^[^\s#])').Value
if (-not $tunnelBaseFn) {
    $tunnelBaseFn = [regex]::Match($gitMode, '(?ms)^tunnel_port_user_base\(\)\s*\{.*?\n\}').Value
}
Assert (
    ($tunnelBaseFn -match 'CONNECT_PORT_BASE:-20000') -and
    ($tunnelBaseFn -match 'offset=\$\(\(\s*uid_str\s*-\s*1000\s*\)\)') -and
    ($tunnelBaseFn -match 'offset\s*\*\s*10')
) 'git-mode.sh tunnel_port_user_base uses 20000 + (UID-1000)*10'

# 6) CM single-quoted so $HOME expands on remote shell, not at local assign
Assert ($mac -match "(?m)^CM='\`$HOME/\.local/bin/claude-mount'\s*$") `
    "CM='\`$HOME/.local/bin/claude-mount' single-quoted (remote expand)"

# 7) _tunnel_alive zombie filter (kill -0 alone is insufficient on macOS)
Assert ($mac -match "_tunnel_alive\(\)\s*\{\s*kill -0.*grep -qv 'Z'") `
    '_tunnel_alive rejects zombie processes (grep -qv Z)'

# 8) Session cleanup traps: EXIT + SIGTERM(143) + SIGHUP(129)
Assert (
    ($mac -match "trap cleanup_session EXIT") -and
    ($mac -match "trap 'cleanup_session; exit 143' SIGTERM") -and
    ($mac -match "trap 'cleanup_session; exit 129' SIGHUP")
) 'session traps install EXIT + SIGTERM + SIGHUP cleanup_session handlers'

# 9) exit_requested menu loop with post-disconnect M/C/X (read_post_disconnect_key)
$postBlock = [regex]::Match($mac, '(?ms)read_post_disconnect_key.*?esac').Value
Assert (
    ($mac -match 'exit_requested=0') -and
    ($mac -match 'while \[ "\$exit_requested" -eq 0 \]') -and
    ($mac -match 'read_post_disconnect_key') -and
    ($postBlock -match '(?m)^\s*m\)') -and
    ($postBlock -match '(?m)^\s*c\)') -and
    ($postBlock -match 'exit_requested=1') -and
    ($gitMode -match 'M = project menu\s+C = connect again\s+X = exit')
) 'exit_requested menu loop handles M/C/X via read_post_disconnect_key'

# 10) clear_session_mount on disconnect / recovery paths
Assert (
    ($mac -match 'clear_session_mount') -and
    ($gitMode -match 'clear_session_mount\(\)') -and
    ($mac -match "clear_session_mount.*user_quit|clear_session_mount.*auto_recovery|clear_session_mount.*unexpected_disconnect")
) 'connect.sh calls clear_session_mount on session end / recovery'

# 11) initialize_server_session wired to Server setup step
Assert (
    ($mac -match 'step "Server setup"') -and
    ($mac -match 'initialize_server_session "\$_script_dir"') -and
    ($gitMode -match 'initialize_server_session\(\)')
) 'mac/connect.sh runs initialize_server_session for Server setup'

# 12) FAIL DIE + FAIL STEP structured error logging
Assert (
    ($mac -match 'connect_log "FAIL DIE:') -and
    ($mac -match 'connect_log "FAIL STEP name=')
) 'mac/connect.sh die() and step_fail() emit FAIL DIE / FAIL STEP logs'

# 13) soft_fail_exhausted_keep_alive (tunnel sync debounce parity)
Assert ($gitMode -match 'TUNNEL_SYNC soft_fail_exhausted_keep_alive') `
    'git-mode.sh keeps session alive after soft_fail budget exhausted (TCP open, no ssh proc)'

# 14) skip_press_o_warn when already on folder after POST_TUNNEL_RECOVERY
Assert (
    ($mac -match 'POST_TUNNEL_RECOVERY') -and
    ($mac -match 'skip_press_o_warn reason=already_on_folder') -and
    ($mac -match 'press O if Cursor is not on the project folder')
) 'post-tunnel recovery skips press-O warn when editor already on folder'

Write-Host ''
Write-Host "Asserts: $assertCount  Passed: $($assertCount - $fail)  Failed: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
exit 0
