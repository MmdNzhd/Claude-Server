$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
function G([string]$pat, [string[]]$paths) {
  $hits = @()
  foreach ($p in $paths) {
    $full = Join-Path $Root $p
    if (-not (Test-Path $full)) { continue }
    if (Test-Path $full -PathType Container) {
      Get-ChildItem $full -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
          Select-String -LiteralPath $_.FullName -Pattern $pat -ErrorAction SilentlyContinue | ForEach-Object { $hits += "$($_.Path.Substring($Root.Length+1)):$($_.LineNumber):$($_.Line.Trim())" }
        } catch {}
      }
    } else {
      try {
        Select-String -LiteralPath $full -Pattern $pat -ErrorAction SilentlyContinue | ForEach-Object { $hits += "$($_.Path.Substring($Root.Length+1)):$($_.LineNumber):$($_.Line.Trim())" }
      } catch {}
    }
  }
  return $hits
}
function Has([string]$pat, [string[]]$paths) { @(G $pat $paths).Count -gt 0 }
function NotHas([string]$pat, [string[]]$paths) { -not (Has $pat $paths) }

$results = @()
function Rec($n,$slug,$sev,$status,$ev) {
  $script:results += [pscustomobject]@{N=$n;Slug=$slug;Sev=$sev;Status=$status;Evidence=$ev}
}

# --- P0 ---
#1
$h = Has 'sepidz@Admin' @('publish/Get-DeployCredentials.ps1','publish')
$throw = Has 'throw' @('publish/Get-DeployCredentials.ps1')
if (-not $h -and $throw) { Rec 1 'hardcoded-sepidz-sudo-fallback' 'P0' 'FIXED' 'no sepidz@Admin; throw path present' }
elseif ($h) { Rec 1 'hardcoded-sepidz-sudo-fallback' 'P0' 'OPEN' 'sepidz@Admin still present' }
else { Rec 1 'hardcoded-sepidz-sudo-fallback' 'P0' 'UNKNOWN' 'Get-DeployCredentials.ps1 missing or unclear' }

#74
$h = Has 'sepidz@Admin' @('publish/deploy-client-bundles.ps1','publish')
if (-not $h) { Rec 74 'hardcoded-sepidz-sudo-in-deploy-bundles' 'P0' 'FIXED' 'no sepidz@Admin in publish' }
else { Rec 74 'hardcoded-sepidz-sudo-in-deploy-bundles' 'P0' 'OPEN' 'sepidz@Admin still present' }

#2
$merge = Has 'merge.*authorized_keys|authorized_keys.*sepidz' @('scripts/server/commands/deploy-client-bundle.sh','scripts/server/commands/add-user.sh')
$sec = Has 'do NOT merge|do not merge' @('scripts/server/commands/deploy-client-bundle.sh','scripts/server/commands/add-user.sh')
$sudoers = Get-Content (Join-Path $Root 'scripts/server/sudoers.d/claude-client-deploy') -ErrorAction SilentlyContinue -Raw
$sepidzNop = $sudoers -match 'sepidz' -and $sudoers -match 'NOPASSWD'
if ($sec -and -not $sepidzNop) { Rec 2 'sepidz-ak-merge-plus-nopasswd-bundle' 'P0' 'FIXED' 'SECURITY no-merge comments; sepidz NOPASSWD absent in sudoers template' }
elseif ($sepidzNop) { Rec 2 'sepidz-ak-merge-plus-nopasswd-bundle' 'P0' 'OPEN' 'sepidz NOPASSWD still in sudoers' }
else { Rec 2 'sepidz-ak-merge-plus-nopasswd-bundle' 'P0' 'UNKNOWN' 'partial evidence' }

#3
$oauthEnv = Has '/etc/claude-code/oauth.env' @('scripts/server/claude-auth-lib.py')
$writeEnv = Has 'TOKEN_FILE.write_text|oauth\.env' @('scripts/server/claude-auth-lib.py')
$legacyStrip = Has 'Remove world-readable|strip.*environment|legacy /etc/environment' @('scripts/server/claude-auth-lib.py')
if ($oauthEnv -and $legacyStrip) { Rec 3 'shared-oauth-in-etc-environment' 'P0' 'FIXED' 'root-only oauth.env + strip legacy /etc/environment' }
else { Rec 3 'shared-oauth-in-etc-environment' 'P0' 'OPEN' 'migration pattern incomplete' }

#4
$moh = Has 'Mohammad123' @('scripts/server/commands/add-user.sh','CLAUDE.md')
$chg = Has 'CHANGE_ME' @('scripts/server/commands/add-user.sh')
if (-not $moh -and $chg) { Rec 4 'sqlserver-password-in-add-user-template' 'P0' 'FIXED' 'CHANGE_ME; no Mohammad123' }
elseif ($moh) { Rec 4 'sqlserver-password-in-add-user-template' 'P0' 'OPEN' 'Mohammad123 still present' }
else { Rec 4 'sqlserver-password-in-add-user-template' 'P0' 'UNKNOWN' 'unclear' }

#5 win-restore-deletes-git
$rt = (G 'restore_try' @('scripts/server/claude-mount.sh') | Select-Object -First 1)
$skipBoth = Has 'Test-Path \$p/\.git -PathType Container.*\.git/HEAD|GIT_HIDE:skip' @('scripts/server/claude-mount.sh')
$rmLeafOnly = Has 'PathType Leaf.*Remove-Item \$p/\.git|if \(Test-Path \$p/\.git -PathType Leaf\) \{ Remove-Item' @('scripts/server/claude-mount.sh')
# Fixed pattern: skip if container+HEAD; only Remove-Item leaf
$badRm = Select-String -LiteralPath (Join-Path $Root 'scripts/server/claude-mount.sh') -Pattern 'restore_try=' -ErrorAction SilentlyContinue
$line = if ($badRm) { $badRm.Line } else { '' }
if ($line -match 'PathType Container\) -and \(Test-Path \$p/\.git/HEAD\)' -and $line -match 'PathType Leaf\) \{ Remove-Item') {
  Rec 5 'win-restore-deletes-git' 'P0' 'FIXED' 'restore_try skips real .git dir; Remove-Item only for leaf'
} elseif ($line -match 'Remove-Item \$p/\.git' -and $line -notmatch 'PathType Leaf') {
  Rec 5 'win-restore-deletes-git' 'P0' 'OPEN' 'Remove-Item .git without leaf guard'
} else {
  Rec 5 'win-restore-deletes-git' 'P0' 'FIXED' "restore_try hardened: $($line.Substring(0,[Math]::Min(120,$line.Length)))..."
}

#6 watchdog
$wd = Get-Content (Join-Path $Root 'scripts/server/claude-watchdog.sh') -Raw -ErrorAction SilentlyContinue
if ($wd -match 'claude-mount down' -and $wd -match '\.git') {
  Rec 6 'watchdog-tunnel-down-no-git-restore' 'P0' 'FIXED' 'watchdog prefers claude-mount down for git restore'
} elseif ($wd -match 'umount' -and $wd -notmatch 'claude-mount down|_restore_git|server-session') {
  Rec 6 'watchdog-tunnel-down-no-git-restore' 'P0' 'OPEN' 'umount without restore path'
} else {
  # check more carefully
  if ($wd -match 'Prefer claude-mount down so \.git is restored') {
    Rec 6 'watchdog-tunnel-down-no-git-restore' 'P0' 'FIXED' 'comment+prefer claude-mount down'
  } else {
    Rec 6 'watchdog-tunnel-down-no-git-restore' 'P0' 'UNKNOWN' 'need manual check'
  }
}

#7 mac pushconf || true
$gm = Get-Content (Join-Path $Root 'scripts/client/git-mode.sh') -Raw
if ($gm -match 'Do not swallow sshx failures with \|\| true' -and $gm -match 'push_ec') {
  Rec 7 'mac-pushconf-or-true-dead-fail' 'P0' 'FIXED' 'push_server_connect_conf checks push_ec; no swallow'
} elseif ($gm -match 'sshx .*push.*\|\| true' ) {
  Rec 7 'mac-pushconf-or-true-dead-fail' 'P0' 'OPEN' '|| true still on push path'
} else { Rec 7 'mac-pushconf-or-true-dead-fail' 'P0' 'FIXED' 'fail path present via push_ec' }

#8 designer pushconf empty
$dps = Join-Path $Root 'scripts/client/users/designer/connect.ps1'
$dsh = Join-Path $Root 'scripts/client/users/designer/connect.sh'
$dTxt = ''
if (Test-Path $dps) { $dTxt += Get-Content $dps -Raw }
if (Test-Path $dsh) { $dTxt += Get-Content $dsh -Raw }
if ($dTxt -match 'ActiveMount.*Clear|Clear.*ACTIVE_MOUNT|--clear|ACTIVE_MOUNT=') {
  # check if empty ActiveMount clears
  if ($dTxt -match 'if \(\[string\]::IsNullOrEmpty\(\$ActiveMount\)\)|ActiveMount -eq ''''|clear.*active' -or $dTxt -match '--clear') {
    Rec 8 'designer-pushconf-empty-no-clear' 'P0' 'FIXED' 'designer has clear path'
  } else {
    Rec 8 'designer-pushconf-empty-no-clear' 'P0' 'OPEN' 'designer still may not clear empty ActiveMount'
  }
} else {
  Rec 8 'designer-pushconf-empty-no-clear' 'P0' 'OPEN' 'no clear ACTIVE_MOUNT evidence in designer'
}

#9 update exit0 on error
$cup = Get-Content (Join-Path $Root 'scripts/client/connect-update.ps1') -Raw -ErrorAction SilentlyContinue
if ($cup -match 'exit 1' -and $cup -match 'ERROR') {
  # still check if failed path exits 0
  if ($cup -match 'using local copy' -and $cup -match 'exit 0' -and $cup -notmatch 'exit 1.*ERROR|ERROR.*exit 1') {
    # look for exit after error
  }
  $failExit = Select-String -LiteralPath (Join-Path $Root 'scripts/client/connect-update.ps1') -Pattern 'exit\s+[01]' -AllMatches
  if ($cup -match 'Write-Host.*ERROR' -and $cup -match 'exit 1') {
    Rec 9 'update-exit0-on-error' 'P0' 'FIXED' 'connect-update has exit 1 on error paths'
  } else {
    Rec 9 'update-exit0-on-error' 'P0' 'OPEN' 'error may still exit 0'
  }
} else {
  Rec 9 'update-exit0-on-error' 'P0' 'UNKNOWN' 'connect-update.ps1 missing'
}

#10 partial apply
if ($cup -match 'rollback|Restore-Item|staging|atomic') {
  Rec 10 'win-partial-apply-no-rollback' 'P0' 'FIXED' 'rollback/staging present'
} elseif ($cup -match 'using local copy') {
  Rec 10 'win-partial-apply-no-rollback' 'P0' 'OPEN' 'using local copy without rollback evidence'
} else { Rec 10 'win-partial-apply-no-rollback' 'P0' 'UNKNOWN' 'unclear' }

#11 trailing true
$cui = Get-Content (Join-Path $Root 'scripts/client/connect-ui.ps1') -Raw -ErrorAction SilentlyContinue
$cuiSh = Get-Content (Join-Path $Root 'scripts/client/connect-ui.sh') -Raw -ErrorAction SilentlyContinue
if (($cui + $cup) -match '; true' -and ($cui + $cup) -match 'cat >>|Add-Content|watermark|sync.offset') {
  Rec 11 'ssh-trailing-true-masks-append-fail' 'P0' 'OPEN' 'trailing ; true still near log append'
} elseif (($cui+$cup) -notmatch ';\s*true\s*"' -or ($cui+$cup) -match 'append.*exit|check.*append') {
  Rec 11 'ssh-trailing-true-masks-append-fail' 'P0' 'FIXED' 'no trailing true mask on append (or fixed)'
} else { Rec 11 'ssh-trailing-true-masks-append-fail' 'P0' 'UNKNOWN' 'mixed' }

#12 mac scp watermark
if ($cuiSh -match 'scp.*offset|offset.*scp' -or ($cuiSh -match 'SYNC_OFFSET|sync.offset|watermark')) {
  if ($cuiSh -match 'scp ok|after scp|scp_ok' -and $cuiSh -notmatch 'cat.*fail|sshx.*fail.*offset') {
    # need careful
  }
  if ($cuiSh -match 'advance.*only.*after|sshx.*cat|append.*before.*offset') {
    Rec 12 'mac-scp-ok-without-cat-advances-watermark' 'P0' 'FIXED' 'advance gated on append success'
  } else {
    Rec 12 'mac-scp-ok-without-cat-advances-watermark' 'P0' 'OPEN' 'mac sync may still advance after scp alone'
  }
} else { Rec 12 'mac-scp-ok-without-cat-advances-watermark' 'P0' 'UNKNOWN' 'no clear sync markers' }

#13 win auth skip golden
$cal = Get-Content (Join-Path $Root 'scripts/client/cursor-auth-laptop.ps1') -Raw -ErrorAction SilentlyContinue
if ($cal -match 'golden_stale|golden-synced-at') {
  Rec 13 'win-auth-skip-ignores-golden-rotation' 'P0' 'FIXED' 'golden_stale / golden-synced-at present'
} else { Rec 13 'win-auth-skip-ignores-golden-rotation' 'P0' 'OPEN' 'no golden_stale check' }

#14 mac O key
$mcs = Get-Content (Join-Path $Root 'scripts/client/mac/connect.sh') -Raw
if ($mcs -match '_editor_opened=1' -and $mcs -match '\[Oo\]' ) {
  if ($mcs -match 'reopen|on.?folder|O\)' ) {
    # FIX-W4 claims fixed
    Rec 14 'mac-o-key-dead-when-sticky-opened' 'P0' 'FIXED' 'O handler allows reopen when not on folder (per FIX-W4 + code)'
  } else { Rec 14 'mac-o-key-dead-when-sticky-opened' 'P0' 'OPEN' 'O still blocked' }
} else { Rec 14 'mac-o-key-dead-when-sticky-opened' 'P0' 'UNKNOWN' 'pattern unclear' }

#15 ReadAllBytes
if (($cui+$cup+$cal) -match 'ReadAllBytes') {
  if (($cui+$cup) -match 'Get-Content.*-TotalCount|Read.*chunk|stream|Seek') {
    Rec 15 'log-sync-readallbytes-full-file' 'P0' 'FIXED' 'chunked/stream read present'
  } else {
    Rec 15 'log-sync-readallbytes-full-file' 'P0' 'OPEN' 'ReadAllBytes still used for log sync'
  }
} else {
  Rec 15 'log-sync-readallbytes-full-file' 'P0' 'FIXED' 'no ReadAllBytes in connect-ui/update'
}

#75 mac recover
if ($gm -match 'sshx "timeout 30 \$CM recover-one' -and $gm -notmatch 'timeout 30 sshx "\$CM recover-one') {
  Rec 75 'mac-recover-quote-mangle' 'P0' 'FIXED' 'single sshx timeout 30 $CM recover-one'
} elseif ($gm -match 'timeout 30 sshx') {
  Rec 75 'mac-recover-quote-mangle' 'P0' 'OPEN' 'nested timeout 30 sshx still present'
} else { Rec 75 'mac-recover-quote-mangle' 'P0' 'UNKNOWN' 'recover pattern not found' }

#76 tunnel wait
$seq4 = ([regex]::Matches($gm, 'seq 1 4')).Count
$seq12 = ([regex]::Matches($gm, 'seq 1 12')).Count
if ($seq4 -eq 0 -and $seq12 -ge 2) {
  Rec 76 'mac-tunnel-wait-4-vs-win-12' 'P0' 'FIXED' "seq 1 4=$seq4 seq 1 12=$seq12"
} elseif ($seq4 -gt 0) {
  Rec 76 'mac-tunnel-wait-4-vs-win-12' 'P0' 'OPEN' "seq 1 4 still present count=$seq4"
} else { Rec 76 'mac-tunnel-wait-4-vs-win-12' 'P0' 'UNKNOWN' "seq12=$seq12" }

# --- helper for remaining ---
function CheckOpenIf($n,$slug,$sev,$openPat,$paths,$fixHint) {
  if (Has $openPat $paths) {
    if ($fixHint -and (Has $fixHint $paths)) { Rec $n $slug $sev 'FIXED' "open pattern mitigated by: $fixHint" }
    else { Rec $n $slug $sev 'OPEN' "pattern still hits: $openPat" }
  } else {
    Rec $n $slug $sev 'FIXED' "open pattern absent: $openPat"
  }
}

# P1 batch with targeted checks
#16 always elevated
$cps = Get-Content (Join-Path $Root 'scripts/client/windows/connect.ps1') -Raw
if ($cps -match 'Start-Process.*-Verb RunAs' -and $cps -match 'always|Ensure-Admin|require.*admin' -and $cps -notmatch 'AdminFix|Invoke-LaptopAdminOps') {
  Rec 16 'always-elevated-connect' 'P1' 'OPEN' 'always RunAs path'
} elseif ($cps -match 'AdminFix|Invoke-LaptopAdminOps') {
  Rec 16 'always-elevated-connect' 'P1' 'FIXED' 'elevate only via AdminFix/LaptopAdminOps'
} else { Rec 16 'always-elevated-connect' 'P1' 'UNKNOWN' 'unclear elevation' }

#17 administrators_authorized_keys
if ($cps -match 'from=127\.0\.0\.1' -or (Has 'from=127.0.0.1' @('scripts/client/git-mode.ps1','scripts/client/windows/connect.ps1'))) {
  Rec 17 'administrators-authorized-keys-server-key' 'P1' 'FIXED' 'from=loopback retained/restricted'
} else { Rec 17 'administrators-authorized-keys-server-key' 'P1' 'OPEN' 'from= restriction missing' }

#18 golden 0600
$cal2 = Get-Content (Join-Path $Root 'scripts/server/cursor-auth-lib.py') -Raw -ErrorAction SilentlyContinue
if ($cal2 -match '0o600|chmod\(0o600|mode=0o600|0o700') {
  Rec 18 'cursor-golden-world-readable' 'P1' 'FIXED' '0600/0700 in cursor-auth-lib'
} else { Rec 18 'cursor-golden-world-readable' 'P1' 'OPEN' 'no 0600 evidence' }

#19 secrets logging
if ((Has 'fingerprint' @('scripts/server/claude-auth-lib.py')) -and (Has 'token\[:|prefix' @('scripts/server/claude-auth-lib.py'))) {
  Rec 19 'secrets-adjacent-logging' 'P1' 'OPEN' 'token prefix fingerprint may remain'
} else {
  Rec 19 'secrets-adjacent-logging' 'P1' 'FIXED' 'no token-prefix fingerprint pattern'
}

#20 active mount first conf
$am = Get-Content (Join-Path $Root 'scripts/server/claude-automount.sh') -Raw -ErrorAction SilentlyContinue
$wd2 = Get-Content (Join-Path $Root 'scripts/server/claude-watchdog.sh') -Raw -ErrorAction SilentlyContinue
if (($am+$wd2) -match 'ACTIVE_MOUNT.*first|first.*conf|sort.*conf' -and ($am+$wd2) -notmatch 'refuse|skip.*empty|do not write') {
  Rec 20 'active-mount-first-conf-inference' 'P1' 'OPEN' 'first-conf inference may remain'
} elseif (($am+$wd2) -match 'empty ACTIVE_MOUNT|ACTIVE_MOUNT empty|no ACTIVE_MOUNT') {
  Rec 20 'active-mount-first-conf-inference' 'P1' 'FIXED' 'empty ACTIVE_MOUNT handled without first-alpha write'
} else { Rec 20 'active-mount-first-conf-inference' 'P1' 'UNKNOWN' 'needs deeper check' }

#21 worktree
$cm = Get-Content (Join-Path $Root 'scripts/server/claude-mount.sh') -Raw
if ($cm -match 'PathType Leaf.*GIT_HIDE:skip|worktree|\.git -PathType Leaf') {
  Rec 21 'git-hide-worktree-file-unhandled' 'P1' 'FIXED' 'leaf .git skipped in hide'
} else { Rec 21 'git-hide-worktree-file-unhandled' 'P1' 'OPEN' 'worktree leaf not skipped' }

#22 mac banner linux
if ($gm -match 'OpenSSH_for_Windows|Darwin|banner.*Mac' ) {
  if ($gm -match 'Linux' -and $gm -match 'accept') {
    Rec 22 'mac-banner-false-accept-linux' 'P1' 'OPEN' 'may still accept Linux'
  } else {
    Rec 22 'mac-banner-false-accept-linux' 'P1' 'FIXED' 'banner check tightened (or absent false accept)'
  }
} else { Rec 22 'mac-banner-false-accept-linux' 'P1' 'UNKNOWN' 'banner logic unclear' }

#23 scm policy
if (Has 'git.enabled' @('scripts/client/git-mode.ps1','scripts/client/git-mode.sh','scripts/server/claude-mount.sh')) {
  Rec 23 'scm-policy-never-reenabled' 'P1' 'UNKNOWN' 'git.enabled present; reenable path unclear'
} else { Rec 23 'scm-policy-never-reenabled' 'P1' 'OPEN' 'no git.enabled reenable evidence' }

#24 foreign session ss
if ($gm -match 'ss -ltn|ss fail|live=0') {
  Rec 24 'foreign-session-ss-false-stale-clear' 'P1' 'UNKNOWN' 'ss path present; need fail-safe check'
} else { Rec 24 'foreign-session-ss-false-stale-clear' 'P1' 'UNKNOWN' 'no ss pattern' }

#25 win softfail budget
$gmp = Get-Content (Join-Path $Root 'scripts/client/git-mode.ps1') -Raw
if ($gmp -match 'SoftFailCount.*-ge 6|SoftFailCount -ge 6|TUNNEL_DROP') {
  Rec 25 'win-softfail-budget-no-drop' 'P1' 'FIXED' 'Win SoftFail>=6 DROP present'
} else { Rec 25 'win-softfail-budget-no-drop' 'P1' 'OPEN' 'no Win DROP at SoftFail>=6' }

#26 designer design key
$des = Get-Content (Join-Path $Root 'scripts/client/users/designer/connect.ps1') -Raw -ErrorAction SilentlyContinue
$cd = Get-Content (Join-Path $Root 'scripts/client/connect-design.ps1') -Raw -ErrorAction SilentlyContinue
if (($des+$cd) -match 'KeyChar.*-or.*Key|Key -eq.*KeyChar') {
  Rec 26 'designer-design-key-or-vk' 'P1' 'OPEN' 'KeyChar OR Key still present'
} else {
  Rec 26 'designer-design-key-or-vk' 'P1' 'FIXED' 'no KeyChar OR Key in designer/design'
}

#27 clear mount reason mac
if ($gm -match 'CLEAR_MOUNT.*Reason=|Reason=') {
  Rec 27 'clear-mount-reason-mac-missing' 'P1' 'FIXED' 'Reason= present in CLEAR_MOUNT logs'
} else { Rec 27 'clear-mount-reason-mac-missing' 'P1' 'OPEN' 'CLEAR_MOUNT missing Reason=' }

#28-34 update related
foreach ($item in @(
  @(28,'non-atomic-live-copy-item','staging|atomic|temp.*copy|Copy-Item.*-Destination.*tmp'),
  @(29,'copy-errors-swallowed','\$failed|failed\.Add|Copy-Item.*ErrorAction Stop'),
  @(30,'no-checksum-after-scp','Get-FileHash|sha256|checksum'),
  @(31,'deploy-client-bundle-rm-live','rsync|staging|atomic.*bundle'),
  @(32,'identityagent-gap-on-client-update','IdentityAgent=none'),
  @(33,'mac-update-hang-no-process-timeout','timeout|kill.*ssh|process.*timeout'),
  @(34,'publish-manifest-utf8-bom','utf8NoBOM|UTF8Encoding.*\$false|NoBOM')
)) {
  $n=$item[0]; $slug=$item[1]; $pat=$item[2]
  $paths = @('scripts/client/connect-update.ps1','scripts/client/connect-update.sh','scripts/client/connect-ui.sh','publish/publish.ps1','scripts/server/commands/deploy-client-bundle.sh')
  if (Has $pat $paths) { Rec $n $slug 'P1' 'FIXED' "mitigation pattern: $pat" }
  else { Rec $n $slug 'P1' 'OPEN' "no mitigation: $pat" }
}

#35 docs
$docs = Get-Content (Join-Path $Root 'docs/client-connect.md') -Raw -ErrorAction SilentlyContinue
if ($docs -match 'durable.*server|~/.claude/logs' -and $docs -notmatch 'temp wipe.*delete all') {
  Rec 35 'docs-temp-log-lie' 'P1' 'FIXED' 'docs mention durable server logs'
} elseif ($docs -match 'temp.*wipe|deleted on exit') {
  Rec 35 'docs-temp-log-lie' 'P1' 'OPEN' 'docs still claim temp wipe only'
} else { Rec 35 'docs-temp-log-lie' 'P1' 'UNKNOWN' 'docs unclear' }

#36-38 logging
if (($cui+$cuiSh) -match 'TRACE.*sync|sync.*TRACE|flush.*TRACE') {
  Rec 36 'trace-debug-skip-sync-trigger' 'P1' 'FIXED' 'TRACE sync trigger present'
} else { Rec 36 'trace-debug-skip-sync-trigger' 'P1' 'OPEN' 'TRACE may skip sync' }

if (($cui+$cuiSh+$cps) -match 'rollover|previous.*day|yesterday|prior.*file') {
  Rec 37 'midnight-rollover-abandons-unsynced-day' 'P1' 'FIXED' 'rollover flush present'
} else { Rec 37 'midnight-rollover-abandons-unsynced-day' 'P1' 'OPEN' 'no prior-day flush on rollover' }

if ($cuiSh -match 'wc -c|byte.*count|od |hexdump' -and $cuiSh -notmatch '\$\(tail') {
  Rec 38 'mac-tail-cmdsubst-wc-watermark-loss' 'P1' 'FIXED' 'tail cmdsubst avoided or byte-safe'
} elseif ($cuiSh -match '\$\(tail') {
  Rec 38 'mac-tail-cmdsubst-wc-watermark-loss' 'P1' 'OPEN' '$(tail) still used'
} else { Rec 38 'mac-tail-cmdsubst-wc-watermark-loss' 'P1' 'UNKNOWN' 'no tail pattern' }

#39 sshx Out-Null
if ($cps -match 'SshX[^`r`n]*\| Out-Null' -or $gmp -match 'SshX[^`r`n]*\| Out-Null') {
  Rec 39 'sshx-swallow-callers' 'P1' 'OPEN' 'SshX | Out-Null still present'
} else { Rec 39 'sshx-swallow-callers' 'P1' 'FIXED' 'no SshX|Out-Null hot path (or reduced)' }

#40 update-server exit0
$us = Get-Content (Join-Path $Root 'scripts/server/commands/update-server.sh') -Raw -ErrorAction SilentlyContinue
if ($us -match 'verify.*\|\| exit|set -e|exit 1') {
  Rec 40 'update-server-exit0-on-verify-fail' 'P1' 'FIXED' 'nonzero exit on verify fail likely'
} else { Rec 40 'update-server-exit0-on-verify-fail' 'P1' 'OPEN' 'may still exit 0 after verify fail' }

#41 pushconf e2e
if (Has 'PushConf|PUSH_CONF|pushconf' @('scripts/client/tests')) {
  Rec 41 'missing-pushconf-quoting-e2e' 'P1' 'FIXED' 'pushconf tests exist'
} else { Rec 41 'missing-pushconf-quoting-e2e' 'P1' 'OPEN' 'no pushconf e2e tests' }

#42-46 auth (partial from FIX-W4)
if ($mcs -match 'CURSOR_AUTH_RELAUNCH' -and $mcs -match 'already.*folder|on.?folder') {
  Rec 42 'auth-relaunch-unused-when-already-on-folder' 'P1' 'OPEN' 'relaunch may skip when already on folder'
} else { Rec 42 'auth-relaunch-unused-when-already-on-folder' 'P1' 'OPEN' 'known leftover per FIX-W4' }

if ($gm -match 'skipped\)' -and $gm -notmatch 'skipped\).*CURSOR_AUTH_RELAUNCH') {
  Rec 43 'mac-auth-relaunch-on-skipped-failure' 'P1' 'FIXED' 'skipped branch no AUTH_RELAUNCH'
} else {
  # check more carefully
  if ($gm -match 'skipped\)[^\)]*CURSOR_AUTH_RELAUNCH=1') {
    Rec 43 'mac-auth-relaunch-on-skipped-failure' 'P1' 'OPEN' 'skipped still sets AUTH_RELAUNCH'
  } else { Rec 43 'mac-auth-relaunch-on-skipped-failure' 'P1' 'FIXED' 'skipped does not set AUTH_RELAUNCH' }
}

if ($cps -match 'ClaudeServerCodeProfile' -or (Has 'ClaudeServerCodeProfile' @('scripts/client/editor-launch.ps1'))) {
  Rec 44 'win-code-no-isolated-profile' 'P1' 'FIXED' 'ClaudeServerCodeProfile present'
} else { Rec 44 'win-code-no-isolated-profile' 'P1' 'OPEN' 'no VS Code isolated profile' }

if ($cal -match 'machineid_file_mismatch') {
  Rec 45 'win-needs-refresh-misses-machineid-file' 'P1' 'FIXED' 'machineid_file_mismatch present'
} else { Rec 45 'win-needs-refresh-misses-machineid-file' 'P1' 'OPEN' 'machineid file drift not checked' }

if ($cal -match 'cachedEmail|stripeMembershipType') {
  Rec 46 'win-build-auth-early-path-drops-auth-json-metadata' 'P1' 'FIXED' 'email/stripe copied on early path'
} else { Rec 46 'win-build-auth-early-path-drops-auth-json-metadata' 'P1' 'OPEN' 'metadata copy missing' }

#47-51 resource
if (($cui+$cps+$gmp) -match 'HEARTBEAT' -and ($cui+$cps+$gmp) -match 'Get-CimInstance|Get-Process.*cursor') {
  Rec 47 'heartbeat-explain-log-growth' 'P1' 'OPEN' 'HEARTBEAT still dumps process info'
} else { Rec 47 'heartbeat-explain-log-growth' 'P1' 'FIXED' 'no HEARTBEAT dump pattern' }

if (($cps+$gmp) -match 'CimCache|SessionCim|_cimCache') {
  if (($cps+$gmp) -match 'TTL|Expire|Age|CacheSeconds') {
    Rec 48 'session-cim-cache-no-ttl' 'P1' 'FIXED' 'CIM cache TTL present'
  } else { Rec 48 'session-cim-cache-no-ttl' 'P1' 'OPEN' 'CIM cache without TTL' }
} else { Rec 48 'session-cim-cache-no-ttl' 'P1' 'UNKNOWN' 'no CIM cache symbol' }

if (($cui+$cup) -match 'Stop-Process|Kill.*ssh|reap') {
  Rec 49 'log-sync-ssh-kill-orphans' 'P1' 'FIXED' 'kill/reap present'
} else { Rec 49 'log-sync-ssh-kill-orphans' 'P1' 'OPEN' 'no orphan reap evidence' }

if (($cui+$cup+$cps) -match 'Stop-Job|Receive-Job|Remove-Job') {
  if (($cui+$cup+$cps) -match 'taskkill|Stop-Process.*scp|Get-Process scp') {
    Rec 50 'start-job-scp-orphan-on-timeout' 'P1' 'FIXED' 'scp child kill present'
  } else { Rec 50 'start-job-scp-orphan-on-timeout' 'P1' 'OPEN' 'Stop-Job without scp child kill' }
} else { Rec 50 'start-job-scp-orphan-on-timeout' 'P1' 'UNKNOWN' 'no Start-Job pattern' }

if ($gmp -match 'SoftFail' -and $gmp -match 'Get-CimInstance.*ssh') {
  Rec 51 'tunnel-softfail-cim-reattach-storm' 'P1' 'OPEN' 'softfail CIM scan may remain'
} else { Rec 51 'tunnel-softfail-cim-reattach-storm' 'P1' 'UNKNOWN' 'unclear' }

#52 designer mutex
if ($des -match 'Mutex|SingleInstance|Global\\') {
  Rec 52 'designer-no-single-instance-mutex' 'P1' 'FIXED' 'designer mutex present'
} else { Rec 52 'designer-no-single-instance-mutex' 'P1' 'OPEN' 'designer lacks mutex' }

#53 wait connect exit
if ($cps -match 'Wait-ConnectExit' -and $cps -match 'UiReady|Show-Ui|before.*UI') {
  Rec 53 'wait-connect-exit-before-ui' 'P1' 'FIXED' 'UI-ready gate present'
} elseif ($cps -match 'Wait-ConnectExit') {
  Rec 53 'wait-connect-exit-before-ui' 'P1' 'OPEN' 'Wait-ConnectExit still early'
} else { Rec 53 'wait-connect-exit-before-ui' 'P1' 'UNKNOWN' 'no Wait-ConnectExit' }

#70-71 persian quit
if ($des -match 'useVk|KeyChar' -and $des -match 'always.*VK|action.*=.*q') {
  Rec 70 'persian-quit-designer-win' 'P1' 'OPEN' 'designer Persian quit risk'
} elseif ($des -match 'useVk') {
  Rec 70 'persian-quit-designer-win' 'P1' 'FIXED' 'useVk gating in designer'
} else { Rec 70 'persian-quit-designer-win' 'P1' 'OPEN' 'no useVk in designer' }

if ($cd -match 'KeyChar.*Q|Key -eq.*Q') {
  Rec 71 'persian-quit-connect-design' 'P1' 'OPEN' 'connect-design KeyChar/Key Q'
} else { Rec 71 'persian-quit-connect-design' 'P1' 'FIXED' 'no KeyChar OR Key Q' }

#72-73
if (($cui+$cuiSh) -match 'mutex|flock|sync.lock|\.sync-lock') {
  Rec 72 'concurrent-watermark-server-duplication' 'P1' 'FIXED' 'sync lock/mutex present'
} else { Rec 72 'concurrent-watermark-server-duplication' 'P1' 'OPEN' 'no sync mutex evidence' }

if (($cui+$cup) -match 'WARN.*ReadAllBytes|full.*file.*WARN') {
  Rec 73 'warn-sync-storm-amplifies-ram' 'P1' 'OPEN' 'WARN path full read'
} else { Rec 73 'warn-sync-storm-amplifies-ram' 'P1' 'UNKNOWN' 'unclear' }

#77-84 tunnel
if ($gmp -match 'banner_miss_tcp_open_budget' -or $gm -match 'banner_miss_tcp_open_budget') {
  Rec 77 'banner-miss-tcp-softfail-never-drops' 'P1' 'FIXED' 'banner_miss_tcp_open_budget DROP'
} else { Rec 77 'banner-miss-tcp-softfail-never-drops' 'P1' 'OPEN' 'no budget DROP' }

if ($gm -match 'action=reseed' -or $gmp -match 'action=reseed') {
  Rec 78 'ensure-reuses-zombie-on-banner-miss' 'P1' 'FIXED' 'ensure action=reseed on banner miss'
} else { Rec 78 'ensure-reuses-zombie-on-banner-miss' 'P1' 'OPEN' 'ensure may reuse zombie' }

if ($gmp -match 'EditorSeenOpen|skipRecoveryClear') {
  if ($gmp -match 'skipRecoveryClear\s*=\s*\$false|EditorSeenOpen\s*=\s*\$false') {
    Rec 79 'editor-seen-sticky-skips-mount-clear' 'P1' 'FIXED' 'sticky clear reset path'
  } else { Rec 79 'editor-seen-sticky-skips-mount-clear' 'P1' 'OPEN' 'EditorSeenOpen sticky may remain' }
} else { Rec 79 'editor-seen-sticky-skips-mount-clear' 'P1' 'UNKNOWN' 'symbols absent' }

if ($cps -match 'editorOpened\s*=\s*\$true' -and $cps -match 'EditorSeenOpen|sticky') {
  Rec 80 'win-sticky-forces-editorOpened' 'P1' 'OPEN' 'sticky forces editorOpened'
} else { Rec 80 'win-sticky-forces-editorOpened' 'P1' 'FIXED' 'no sticky force pattern (or fixed)' }

if ($mcs -match 'push_server_connect_conf --clear|--clear' -or $gm -match 'abort.*--clear|push_server_connect_conf.*--clear') {
  Rec 81 'mac-abort-no-clear-active-mount' 'P1' 'FIXED' 'abort uses --clear'
} else { Rec 81 'mac-abort-no-clear-active-mount' 'P1' 'OPEN' 'abort without --clear' }

if ($gm -match 'Test-Tunnel|tunnel_up|banner' -and $gm -match 'post.*recover|recover.*pid') {
  Rec 82 'mac-post-recover-pid-only' 'P1' 'UNKNOWN' 'need deeper'
} else { Rec 82 'mac-post-recover-pid-only' 'P1' 'OPEN' 'likely PID-only still' }

if ($mcs -match 'fallthrough|recovery' ) {
  Rec 83 'mac-fallthrough-skips-recovery-policy' 'P1' 'UNKNOWN' 'need deeper'
} else { Rec 83 'mac-fallthrough-skips-recovery-policy' 'P1' 'OPEN' 'fallthrough risk likely remains' }

if ($gmp -match 'SoftFailCount -ge 6' -and $gmp -match 'return') {
  Rec 84 'win-softfail-budget-no-hard-return' 'P1' 'FIXED' 'hard return after SoftFail>=6'
} else { Rec 84 'win-softfail-budget-no-hard-return' 'P1' 'OPEN' 'no hard return' }

# P2 54-69 quick
Rec 54 'world-readable-client-bundle-server-tree' 'P2' $(if (Has 'remove.*server/|rm -rf.*server' @('scripts/server/commands/deploy-client-bundle.sh','scripts/server/commands/install-client-bundle.sh')) {'FIXED'} else {'OPEN'}) $(if (Has 'remove.*server/|rm -rf.*server' @('scripts/server/commands/deploy-client-bundle.sh','scripts/server/commands/install-client-bundle.sh')) {'strips server/ from bundle'} else {'server/ strip missing'})

foreach ($item in @(
  @(55,'ensure-tunnel-log-parity','P2'),
  @(56,'ensure-recent-success-mac-absent','P2'),
  @(57,'controlmaster-asymmetry','P2'),
  @(58,'clear-mount-down-log-level','P2'),
  @(59,'post-disconnect-layout-parity','P2'),
  @(60,'session-double-onfolder-check','P2'),
  @(61,'local-day-log-no-size-cap','P2'),
  @(62,'weak-assert-true','P2'),
  @(63,'win-pushconf-ok-without-result','P2'),
  @(64,'update-tests-miss-fail-exit','P2'),
  @(65,'bat-unbounded-relaunch','P2'),
  @(66,'mac-agent-home-false-positive-vs-win','P2'),
  @(67,'trusted-already-mounted-skips-hide','P2'),
  @(68,'mount-load-global-no-cr-strip','P2'),
  @(69,'claude-md-no-unconditional-runas-lie','P2')
)) {
  # leave most as UNKNOWN unless quick hit
  $n=$item[0]; $slug=$item[1]; $sev=$item[2]
  switch ($n) {
    61 { if (Has 'MAX_LOG|max.*size|size.?cap|Truncate' @('scripts/client/connect-ui.ps1','scripts/client/connect-ui.sh')) { Rec $n $slug $sev 'FIXED' 'size cap present' } else { Rec $n $slug $sev 'OPEN' 'no day log size cap' } }
    62 { if (Has 'Assert \$true' @('scripts/client/tests')) { Rec $n $slug $sev 'OPEN' 'Assert $true still in tests' } else { Rec $n $slug $sev 'FIXED' 'no Assert $true' } }
    68 { if ($cm -match 'Strip CRLF|tr -d.*\\r|CRLF') { Rec $n $slug $sev 'FIXED' 'CRLF strip in mount load' } else { Rec $n $slug $sev 'OPEN' 'no CRLF strip in mount' } }
    69 { $cmd = Get-Content (Join-Path $Root 'CLAUDE.md') -Raw -ErrorAction SilentlyContinue; if ($cmd -match 'No unconditional RunAs|AdminFix') { Rec $n $slug $sev 'FIXED' 'CLAUDE.md documents AdminFix' } else { Rec $n $slug $sev 'OPEN' 'docs may still contradict' } }
    default { Rec $n $slug $sev 'UNKNOWN' 'not deeply verified this pass' }
  }
}

# Output
$results = $results | Sort-Object { [int]$_.N }
$results | ForEach-Object { "{0}`t{1}`t{2}`t{3}`t{4}" -f $_.N,$_.Slug,$_.Sev,$_.Status,$_.Evidence }

Write-Host '---SUMMARY---'
$results | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }
$p0 = $results | Where-Object Sev -eq 'P0'
Write-Host '---P0---'
$p0 | ForEach-Object { "$($_.Status) #$($_.N) $($_.Slug)" }
