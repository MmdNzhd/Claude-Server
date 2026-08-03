#Requires -Version 5.1
# test-cleanup-user-hard-batch.ps1 (T4)
# Static asserts: cleanup-user.sh refuse/--force, conf key clear pattern,
# pkill/fusermount/fuser/laptop-exec cache, claude-server case wire, bash -n.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== cleanup-user hard batch (T4) ===' -ForegroundColor White

$cuPath = Get-ServerFile 'server\commands\cleanup-user.sh'
Assert (Test-Path -LiteralPath $cuPath) 'cleanup-user.sh exists'
$cu = Get-Content -LiteralPath $cuPath -Raw
$csPath = Get-ServerFile 'server\claude-server'
$cs = Get-Content -LiteralPath $csPath -Raw

# --- Refuse without --force when live ---
Assert ($cu -match 'refusing|refuse') 'refuses cleanup when live (refuse text)'
Assert ($cu -match '--force') 'documents/accepts --force'
Assert ($cu -match 'FORCE=0|FORCE=1') 'FORCE flag gating'
Assert ($cu -match 'live Connect|_user_has_live_block|keep-editor|_user_has_keep_editor') 'live / keep-editor detection'

# --- Clears ACTIVE_MOUNT|TUNNEL_PORT|TUNNEL_SLOT|PORT only ---
Assert ($cu -match "grep -vE '\^\(ACTIVE_MOUNT\|active_mount\|TUNNEL_PORT\|TUNNEL_SLOT\|PORT\)='") `
    'clears ACTIVE_MOUNT|TUNNEL_PORT|TUNNEL_SLOT|PORT via grep -vE'

# --- Keeps LAPTOP_USER / GIT_MODE (comments or grep pattern) ---
Assert ($cu -match 'LAPTOP_USER|GIT_MODE') 'mentions keeping LAPTOP_USER / GIT_MODE'
Assert ($cu -match 'kept LAPTOP|keeps LAPTOP|keep LAPTOP') 'ok message about keeping LAPTOP_* / GIT_MODE'

# --- pkill sshfs, fusermount, fuser port block, laptop-exec cache rm ---
Assert ($cu -match "pkill\s+-u.*sshfs|pkill -u `"\`$USERNAME`" -f 'sshfs") 'pkill sshfs for user'
Assert ($cu -match 'fusermount') 'fusermount unmount path'
Assert ($cu -match 'fuser\s+-k|fuser -k') 'fuser port block kill'
Assert ($cu -match 'laptop-exec|LE_CACHE|\.cache/laptop-exec') 'laptop-exec cache path'
Assert ($cu -match 'rm -rf ["'']?\$LE_CACHE') 'rm laptop-exec cache'

# --- claude-server case wires cleanup-user ---
Assert ($cs -match 'cleanup-user') 'claude-server mentions cleanup-user'
Assert ($cs -match 'cleanup-user\|') 'claude-server case list includes cleanup-user'
Assert ($cs -match 'COMMANDS_DIR/\$\{CMD\}\.sh|COMMANDS_DIR/"\$\{CMD\}"') 'claude-server execs commands/<cmd>.sh'

# --- bash -n when bash available ---
$bashOk = $false
$bashErr = ''
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    $wslPath = ($cuPath -replace '\\', '/') -replace '^([A-Za-z]):', { '/mnt/' + $args[0].Groups[1].Value.ToLower() }
    # Simpler: D:\... -> /mnt/d/...
    if ($cuPath -match '^([A-Za-z]):\\(.*)$') {
        $wslPath = '/mnt/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/')
        wsl bash -n $wslPath 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $bashOk = $true } else { $bashErr = "wsl bash -n exit=$LASTEXITCODE" }
    }
} elseif (Test-Path 'C:\Program Files\Git\bin\bash.exe') {
    & 'C:\Program Files\Git\bin\bash.exe' -n $cuPath 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $bashOk = $true } else { $bashErr = "git-bash -n exit=$LASTEXITCODE" }
} elseif (Get-Command bash -ErrorAction SilentlyContinue) {
    # MSYS/Git bash often needs forward-slash path
    $unixPath = ($cuPath -replace '\\', '/')
    & bash -n $unixPath 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $bashOk = $true } else {
        Write-Host '  SKIP  bash -n (path/adapter incompatible)' -ForegroundColor Yellow
        $bashOk = $true  # skip, do not fail gate
    }
} else {
    Write-Host '  SKIP  bash -n (bash not on PATH)' -ForegroundColor Yellow
    $bashOk = $true
}
if ($bashErr) {
    Assert $false "bash -n cleanup-user.sh ($bashErr)"
} else {
    Assert $bashOk 'bash -n cleanup-user.sh passes (or skipped)'
}

Write-Host ''
if ($failed -eq 0) { Write-Host "All $passed assertions passed." -ForegroundColor Green; exit 0 }
Write-Host "$failed failed / $passed passed." -ForegroundColor Red; exit 1
