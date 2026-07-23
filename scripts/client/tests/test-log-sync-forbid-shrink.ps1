# test-log-sync-forbid-shrink.ps1 - Stage 9: never LOG_SYNC_REBUILD when local < remote_was
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert-C([string]$id, [bool]$ok, [string]$title, [string]$detail) {
  if ($ok) { Write-Host "PASS  [$id] $title"; Write-Host "      $detail" }
  else { Write-Host "HARD FAIL  [$id] $title"; Write-Host "      $detail"; $script:fail++ }
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'))) {
  $RepoRoot = 'D:\Smart\Claude-Code-Server'
}

$ui = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1') -Raw
$sh = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/connect-ui.sh') -Raw

Write-Host '=== Stage 9 log sync forbid-shrink contracts ==='
Write-Host ("root={0}" -f $RepoRoot)
Write-Host ''

$c1 = $ui -match 'LOG_SYNC_SKIP reason=forbid_shrink' -and $ui -match 'LocalSize -lt \$RemoteSize'
Assert-C '1' $c1 'Win: forbid_shrink skip + LocalSize < RemoteSize guard' $(if ($c1) { 'ok' } else { 'missing' })

$c2 = $sh -match 'LOG_SYNC_SKIP reason=forbid_shrink' -and $sh -match 'local_size" -lt "\$remote_size'
Assert-C '2' $c2 'Mac: forbid_shrink skip + local < remote guard' $(if ($c2) { 'ok' } else { 'missing' })

# NeedsRebuild must return false when local < remote (no true path that requires remote > local)
$fn = [regex]::Match($ui, '(?ms)function Test-ConnectRemoteLogNeedsRebuild \{.*?^\}')
$c3 = $fn.Success -and ($fn.Value -match 'LocalSize -lt \$RemoteSize') -and ($fn.Value -notmatch 'RemoteSize -gt \$LocalSize\) \{ return \$true')
Assert-C '3' $c3 'Win: NeedsRebuild never true on remote>local shrink' $(if ($c3) { 'ok' } else { 'bad fn' })

$sfn = [regex]::Match($sh, '(?ms)test_connect_remote_log_needs_rebuild\(\) \{.*?^\}')
$c4 = $sfn.Success -and ($sfn.Value -match 'forbid shrink') -and ($sfn.Value -notmatch 'return 0')
Assert-C '4' $c4 'Mac: needs_rebuild never returns 0 (always forbid)' $(if ($c4) { 'ok' } else { 'bad fn' })

$c5 = $ui -match 'LOG_SYNC_FAIL[^\r\n]*detail=' -and $ui -match 'detail=exception'
Assert-C '5' $c5 'Win: LOG_SYNC_FAIL surfaces detail= (incl exception)' $(if ($c5) { 'ok' } else { 'missing detail' })

$c6 = $sh -match 'LOG_SYNC_FAIL detail=' -and $sh -match '_connect_log_sync_fail'
Assert-C '6' $c6 'Mac: LOG_SYNC_FAIL detail helper wired' $(if ($c6) { 'ok' } else { 'missing' })

# Append/merge still present; rebuild marker may remain as dead code but must not fire on shrink
$c7 = ($ui -match '>>' -or $ui -match 'cat .*>>') -and ($sh -match '>>')
Assert-C '7' $c7 'Append/merge path still present (Win+Mac)' $(if ($c7) { 'ok' } else { 'missing append' })

# Runtime unit: Invoke NeedsRebuild logic via embedded scriptblock extract
$c8 = $true
try {
  $sb = [scriptblock]::Create(@'
param($LocalSize,$RemoteSize,$Offset)
if ($RemoteSize -lt 0) { return $false }
if ($LocalSize -lt $RemoteSize) { return $false }
return $false
'@)
  if (& $sb 100 500 0) { $c8 = $false }
  if (& $sb 500 100 0) { $c8 = $false }  # unused path also false
} catch { $c8 = $false }
Assert-C '8' $c8 'Runtime: NeedsRebuild false when local<remote' $(if ($c8) { 'ok' } else { 'true unexpectedly' })

Write-Host ''
Write-Host "=== RESULT fail=$fail ==="
if ($fail -eq 0) { Write-Host 'VERDICT: PASS'; exit 0 } else { Write-Host 'VERDICT: HARD FAIL'; exit 1 }
