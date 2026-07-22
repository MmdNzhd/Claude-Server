Set-Location D:\Smart\Claude-Code-Server
$utf8 = New-Object System.Text.UTF8Encoding $false
$path = Resolve-Path 'scripts/client/users/designer/connect.sh'
$t = [IO.File]::ReadAllText($path)
if ($t -match 'enter_connect_single_instance') {
  Write-Host 'already has enter_connect_single_instance'
  exit 0
}
$insert = @'

# Share Global Connect lock with main connect (one UI per machine).
enter_connect_single_instance() {
    local lockdir="${HOME}/.config/claude-connect"
    local lockfile="${lockdir}/connect.lock"
    mkdir -p "$lockdir" 2>/dev/null || true
    exec 9>"$lockfile" || return 1
    if ! flock -n 9; then
        _designer_log "SINGLE_INSTANCE: blocked pid=$$" ERROR
        printf '\n  [X] Another Claude Connect is already running.\n\n' >&2
        return 1
    fi
    CONNECT_LOCK_HELD=1
    _designer_log "SINGLE_INSTANCE: acquired pid=$$" INFO
    return 0
}
exit_connect_single_instance() {
    if [ "${CONNECT_LOCK_HELD:-0}" = 1 ]; then
        flock -u 9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
        CONNECT_LOCK_HELD=0
    fi
}

'@
# Insert after die/warn helpers block — before "if [ "$(id -u)" -eq 0 ]"
$marker = 'if [ "$(id -u)" -eq 0 ]; then'
if (-not $t.Contains($marker)) { throw "marker not found" }
$t2 = $t.Replace($marker, ($insert + $marker))
# After root check block, acquire lock
$rootBlock = @"
if [ "`$(id -u)" -eq 0 ]; then
    die "Do not run with sudo. Run as your normal user: bash connect.sh"
fi
"@
# Use actual content from file
$afterRoot = @'
if [ "$(id -u)" -eq 0 ]; then
    die "Do not run with sudo. Run as your normal user: bash connect.sh"
fi

if ! enter_connect_single_instance; then
    exit 1
fi
'@
if ($t2 -notmatch 'if ! enter_connect_single_instance') {
  $oldRoot = @'
if [ "$(id -u)" -eq 0 ]; then
    die "Do not run with sudo. Run as your normal user: bash connect.sh"
fi
'@
  if (-not $t2.Contains($oldRoot)) { throw 'root block not found for call insert' }
  $t2 = $t2.Replace($oldRoot, $afterRoot)
}
[IO.File]::WriteAllText($path, $t2, $utf8)
Write-Host 'OK designer Mac single-instance flock' -ForegroundColor Green
# bash -n
& bash -n $path
if ($LASTEXITCODE -ne 0) { throw 'bash -n failed' }
Write-Host 'OK bash -n designer connect.sh' -ForegroundColor Green
