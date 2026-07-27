#Requires -Version 5.1
# test-designer-connect-hard-batch.ps1
# Static hard-batch regression for designer connect invariants (CLAUDE.md Designer Script Invariants).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$failed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Designer connect hard-batch (static invariants) ===' -ForegroundColor Cyan
Write-Host ''

$desPs1 = Get-Content (Get-ClientFile 'users\designer\connect.ps1') -Raw
$desSh  = Get-Content (Get-ClientFile 'users\designer\connect.sh') -Raw
$desReadme = Get-Content (Get-ClientFile 'users\designer\README.md') -Raw
$publishPs1 = Get-Content (Join-Path $script:RepoRoot 'publish\publish.ps1') -Raw

# 1. Mac designer registers EXIT + SIGTERM + SIGHUP cleanup traps
Assert (
    ($desSh -match 'trap cleanup_session EXIT') -and
    ($desSh -match "trap 'cleanup_session; exit 143' SIGTERM") -and
    ($desSh -match "trap 'cleanup_session; exit 129' SIGHUP")
) 'connect.sh registers EXIT+SIGTERM+SIGHUP cleanup traps'

# 2. Windows noVNC flag set only after local port probe succeeds
Assert (
    ($desPs1 -match '(?s)if \(Test-NovncLocal\) \{[\s\S]*?\$novncOpened\s*=\s*\$true') -and
    ($desPs1 -notmatch '(?s)StepFail "noVNC[\s\S]*?\$novncOpened\s*=\s*\$true')
) 'connect.ps1 sets novncOpened only on Test-NovncLocal success'

# 3. Mac noVNC flag set only after novnc_open succeeds
Assert (
    ($desSh -match '(?s)if novnc_open; then[\s\S]*?_novnc_opened=1') -and
    ($desSh -notmatch '(?s)step_fail "noVNC[\s\S]*?_novnc_opened=1')
) 'connect.sh sets _novnc_opened=1 only after novnc_open succeeds'

# 4. Windows manual R reconnect resets autoFixCount (not auto-reconnect continue)
Assert (
    $desPs1 -match '(?s)\$action -ne ''r''[\s\S]*?\$autoFixCount\s*=\s*0'
) 'connect.ps1 resets autoFixCount on manual R reconnect'

# 5. Mac mount list grep -E escapes pipe in mount id (ERE alternation safe)
Assert (
    $desSh -match 'grep -E "\^\$\{MOUNT_ID\}\\\\\|"'
) 'connect.sh grep -E escapes mount-id pipe for ERE'

# 6. Windows conf requires LAPTOP_USER and LAPTOP_PATH
Assert (
    ($desPs1 -match 'if \(-not \$LaptopUser\) \{ Die "Config missing LAPTOP_USER') -and
    ($desPs1 -match 'if \(-not \$LaptopPath\) \{ Die "Config missing LAPTOP_PATH')
) 'connect.ps1 dies when LAPTOP_USER or LAPTOP_PATH missing from conf'

# 7. Mac conf requires LAPTOP_USER and LAPTOP_PATH after sourcing connect.conf
Assert (
    ($desSh -match '\[ -n "\$\{LAPTOP_USER:-\}" \] \|\| die "Config missing LAPTOP_USER') -and
    ($desSh -match '\[ -n "\$\{LAPTOP_PATH:-\}" \] \|\| die "Config missing LAPTOP_PATH')
) 'connect.sh dies when LAPTOP_USER or LAPTOP_PATH missing from conf'

# 8. Windows .ssh ACL grants both interactive USERNAME and LaptopUser when they differ
Assert (
    ($desPs1 -match 'icacls \$SshDir /inheritance:r /grant "\$env:USERNAME`:\(OI\)\(CI\)F"') -and
    ($desPs1 -match 'if \(\$LaptopUser -and \$LaptopUser -ne \$env:USERNAME\) \{[\s\S]*?icacls \$SshDir /grant "\$LaptopUser`:\(OI\)\(CI\)F"')
) 'connect.ps1 icacls .ssh grants USERNAME and LaptopUser when they differ'

# 9. Windows tunnel uses 127.0.0.1 local forward for noVNC (not direct LAN)
Assert (
    $desPs1 -match '"-L", "127\.0\.0\.1:\$\{NovncPort\}:127\.0\.0\.1:\$\{NovncPort\}"'
) 'connect.ps1 SSH tunnel -L binds noVNC on 127.0.0.1 only'

# 10. Mac tunnel uses 127.0.0.1 local forward for noVNC
Assert (
    $desSh -match '-L "127\.0\.0\.1:\$\{NOVNC_PORT\}:127\.0\.0\.1:\$\{NOVNC_PORT\}"'
) 'connect.sh SSH tunnel -L binds noVNC on 127.0.0.1 only'

# 11. Windows honors Enter-ConnectSingleInstance (blocked launch exits, not discarded)
Assert (
    ($desPs1 -match 'Enter-ConnectSingleInstance') -and
    ($desPs1 -match 'if \(-not \(Enter-ConnectSingleInstance\)\)') -and
    ($desPs1 -match 'exit 2')
) 'connect.ps1 honors Enter-ConnectSingleInstance single-instance lock'

# 12. Designer product does not launch Cursor/VS Code editor
Assert (
    ($desPs1 -notmatch 'Launch-RemoteEditor|editor-launch\.ps1|Open-RemoteEditor|Initialize-CursorServerProfile') -and
    ($desSh -notmatch 'editor-launch\.sh|Launch-RemoteEditor')
) 'designer connect does not launch remote editor'

# 13. Repo source ships Smart server IP; README documents Sepidz vs Smart
Assert (
    ($desPs1 -match '\$ServerIP\s*=\s*"192\.168\.210\.240"') -and
    ($desSh -match 'SERVER_IP="192\.168\.210\.240"') -and
    ($desReadme -match '192\.168\.250\.70') -and
    ($desReadme -match '192\.168\.210\.240')
) 'designer source uses Smart IP; README documents Sepidz IP patch'

# 14. publish.ps1 IP-patches designer connect.ps1 and connect.sh for Sepidz package
Assert (
    ($publishPs1 -match 'users\\designer\\connect\.ps1.*PatchIp = \$true') -and
    ($publishPs1 -match 'users\\designer\\connect\.sh.*PatchIp = \$true')
) 'publish.ps1 IP-patches designer connect.ps1 and connect.sh for Sepidz'

$assertCount = 14
Write-Host ''
if ($failed -gt 0) {
    Write-Host "FAILED $failed / $assertCount asserts" -ForegroundColor Red
    exit 1
}
Write-Host "All $assertCount designer hard-batch asserts passed" -ForegroundColor Green
exit 0
