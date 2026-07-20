# test-mount-contracts.ps1 - HARD static contracts for mount/watchdog (Agent P)
$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $Root 'scripts\server\claude-mount.sh'))) {
  $Root = (Get-Location).Path
}
$M = Join-Path $Root 'scripts\server\claude-mount.sh'
$W = Join-Path $Root 'scripts\server\claude-watchdog.sh'
$A = Join-Path $Root 'scripts\server\claude-automount.sh'
$script:fail = 0
function Fail([string]$msg) { $script:fail++; Write-Host "FAIL: $msg" }
function Pass([string]$msg) { Write-Host "PASS: $msg" }

foreach ($f in @($M,$W,$A)) {
  if (-not (Test-Path $f)) { Fail "missing $f" }
}
$mt = [IO.File]::ReadAllText($M)
$wt = [IO.File]::ReadAllText($W)
$at = [IO.File]::ReadAllText($A)

# C1: restore must NOT Remove-Item -Recurse .git
$rx = 'Remove-Item[^\r\n]*\.git[^\r\n]*-Recurse|-Recurse[^\r\n]*\.git'
if ([regex]::IsMatch($mt, $rx)) {
  Fail 'restore uses Remove-Item -Recurse on .git'
} else {
  Pass 'no Remove-Item -Recurse on .git'
}
$i = $mt.IndexOf('_restore_git_body()')
if ($i -ge 0) {
  $body = $mt.Substring($i, [Math]::Min(500, $mt.Length - $i))
  if ($body -match 'Remove-Item') { Fail '_restore_git_body still Remove-Items .git' }
  else { Pass '_restore_git_body has no Remove-Item (rename-only)' }
} else {
  Fail '_restore_git_body missing'
}

# C2: watchdog tunnel DOWN restores .git before/with umount
$downIdx = $wt.IndexOf('if ! tunnel_up')
if ($downIdx -lt 0) { Fail 'watchdog missing tunnel_up DOWN branch' }
else {
  $downChunk = $wt.Substring($downIdx, [Math]::Min(1200, $wt.Length - $downIdx))
  $hasRestore = ($downChunk -match 'restore') -or ($downChunk -match '_restore_git') -or ($downChunk -match '\.git\.server-session') -or ($downChunk -match 'recover')
  $hasUmount = ($downChunk -match '_umount_path') -or ($downChunk -match 'fusermount')
  if ($hasUmount -and $hasRestore) { Pass 'watchdog DOWN restores git with/before umount' }
  elseif ($hasUmount) { Fail 'watchdog tunnel DOWN umounts but does NOT restore .git from .git.server-session' }
  else { Fail 'watchdog DOWN branch incomplete' }
}

# C3: empty ACTIVE_MOUNT must NOT pick first alphabetical conf
$alphaWatch = $false
$wi = $wt.IndexOf('_infer_active()')
if ($wi -ge 0) {
  $infer = $wt.Substring($wi, [Math]::Min(2000, $wt.Length - $wi))
  if ($infer -match '\[ -n "\$name" \] && \{ printf') { $alphaWatch = $true }
}
$alphaAuto = $false
if ($at -match 'ACTIVE_MOUNT="\$_id"; break') { $alphaAuto = $true }
if ($alphaWatch -or $alphaAuto) {
  Fail ("empty ACTIVE_MOUNT can pick first alphabetical conf (watchdog=$alphaWatch automount=$alphaAuto)")
} else {
  Pass 'empty ACTIVE_MOUNT does not alphabetical-fallback'
}

# C4: TUNNEL_PORT CR strip in mount load path
$li = $mt.IndexOf('_load_global()')
if ($li -lt 0) { Fail 'mount _load_global missing' }
else {
  $loadBody = $mt.Substring($li, [Math]::Min(900, $mt.Length - $li))
  if ($loadBody -match 'tr -d') { Pass 'mount _load_global strips CR (tr -d present)' }
  else { Fail 'mount _load_global does NOT strip CR from TUNNEL_PORT' }
}

# C5: worktree .git FILE skipped in hide — must be in live hide_try PS, not comment-only
$hi = $mt.IndexOf('hide_try=')
if ($hi -lt 0) { Fail 'hide_try missing' }
else {
  $hideTry = $mt.Substring($hi, [Math]::Min(900, $mt.Length - $hi))
  if ($hideTry -match 'PathType') {
    Pass 'hide_try skips worktree .git file (PathType check)'
  } else {
    Fail 'worktree .git file not skipped in hide_try (no PathType Container in live PS)'
  }
}

Write-Host ''
if ($script:fail -gt 0) {
  Write-Host "HARD FAIL: $($script:fail) contract(s) missed"
  exit 1
} else {
  Write-Host 'HARD PASS: all mount contracts'
  exit 0
}
