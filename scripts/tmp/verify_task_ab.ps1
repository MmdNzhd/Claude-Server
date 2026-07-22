$ErrorActionPreference = 'Continue'
$fail = 0
function Ok($m) { Write-Host "PASS $m" -ForegroundColor Green }
function Bad($m) { Write-Host "FAIL $m" -ForegroundColor Red; $script:fail++ }

foreach ($f in @(
  'scripts\client\connect-ui.ps1',
  'scripts\client\cursor-auth-laptop.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\windows\connect.ps1'
)) {
  $errs = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$errs)
  if ($errs) { Bad "parse $f"; $errs | ForEach-Object { $_.ToString() } } else { Ok "parse $f" }
}

$ui = Get-Content scripts\client\connect-ui.ps1 -Raw
foreach ($m in @('LOG_SYNC_RECONCILE','Test-ConnectLogChunkAlreadyRemote','size_verify','Clear-ConnectLogSyncPending','Get-ConnectRemoteLogByteSize')) {
  if ($ui -match [regex]::Escape($m)) { Ok "ui:$m" } else { Bad "ui:$m" }
}

$auth = Get-Content scripts\client\cursor-auth-laptop.ps1 -Raw
if ($auth -match 'AUTH_SYNC_BATCH_PROBE') { Ok 'auth batch probe' } else { Bad 'auth batch probe' }
$before = [regex]::Match($auth, 'AUTH_SYNC_BATCH_PROBE(?s).*?already-complete BEFORE').Value
if ($before -and ($before -notmatch 'SshX[\s\S]*cursor-auth-sync --force')) { Ok 'force after already-complete' } else { Bad 'force ordering' }
$forceCalls = ([regex]::Matches($auth, 'SshX "cursor-auth-sync --force')).Count
if ($forceCalls -eq 1) { Ok "force call sites=$forceCalls" } else { Bad "force call sites=$forceCalls" }

$gm = Get-Content scripts\client\git-mode.ps1 -Raw
if ($gm -match 'Batch touch\+chmod\+probe') { Ok 'probe batched' } else { Bad 'probe batched' }
if ($gm -match 'LastPushConfActive') { Ok 'LastPushConfActive' } else { Bad 'LastPushConfActive' }

$cp = Get-Content scripts\client\windows\connect.ps1 -Raw
if ($cp -match 'Skip extra SSH when Push-ServerConnectConf') { Ok 'skip ACTIVE_MOUNT grep' } else { Bad 'skip ACTIVE_MOUNT grep' }
if ($cp -match 'hangs on') { Ok 'ControlMaster hang note' } else { Bad 'ControlMaster hang note' }

$sh = Get-Content scripts\client\connect-ui.sh -Raw
if ($sh -match 'LOG_SYNC_RECONCILE') { Ok 'mac reconcile' } else { Bad 'mac reconcile' }

Write-Host ''
Write-Host '=== hard suite ==='
& powershell -NoProfile -File scripts\client\tests\test-hard-multi-agent-regressions.ps1
if ($LASTEXITCODE -ne 0) { $fail++ }
& powershell -NoProfile -File scripts\client\tests\test-session-log-contracts.ps1
if ($LASTEXITCODE -ne 0) { $fail++ }

if ($fail -eq 0) { Write-Host 'TASK A/B VERIFY OK' -ForegroundColor Green; exit 0 }
Write-Host "TASK A/B VERIFY FAILURES=$fail" -ForegroundColor Red; exit 1
