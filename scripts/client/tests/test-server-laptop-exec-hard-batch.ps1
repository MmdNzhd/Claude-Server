#Requires -Version 5.1
# test-server-laptop-exec-hard-batch.ps1
# Static fail-closed gate: laptop-exec server invariants (hooks, mux, rg, deploy).
# Does NOT edit run-all.ps1; safe to run standalone from repo checkout.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== HARD: server laptop-exec batch invariants ===' -ForegroundColor White
Write-Host ''

$le       = Get-ServerFile 'server\laptop-exec.sh'
$setup    = Get-ServerFile 'server\laptop-exec-setup.sh'
$deploy   = Get-ServerFile 'server\commands\deploy-laptop-exec.sh'
$install  = Get-ServerFile 'server\commands\install.sh'
$mount    = Get-ServerFile 'server\claude-mount.sh'
$heal     = Get-ServerFile 'server\claude-self-heal.sh'
$push     = Get-ServerFile 'server\claude-client-push-laptop.sh'
$sudo     = Get-ServerFile 'server\sudo-from-laptop.sh'
$wrap     = Get-ServerFile 'server\cursor-hooks\laptop-exec-guard-wrap.sh'
$hooksUser = Get-ServerFile 'server\cursor-hooks\hooks-user.json'
$hooksProj = Get-ServerFile 'server\cursor-hooks\hooks-project.json'

$leSrc      = Get-Content -LiteralPath $le -Raw
$setupSrc   = Get-Content -LiteralPath $setup -Raw
$deploySrc  = Get-Content -LiteralPath $deploy -Raw
$installSrc = Get-Content -LiteralPath $install -Raw
$mountSrc   = Get-Content -LiteralPath $mount -Raw
$healSrc    = Get-Content -LiteralPath $heal -Raw
$pushSrc    = Get-Content -LiteralPath $push -Raw
$wrapSrc    = Get-Content -LiteralPath $wrap -Raw
$hooksUserSrc = Get-Content -LiteralPath $hooksUser -Raw
$hooksProjSrc = (Get-Content -LiteralPath $hooksProj -Raw).Trim()

Assert ($hooksProjSrc -eq '{"version":1,"hooks":{}}') 'hooks-project.json is {"version":1,"hooks":{}}'
Assert ($setupSrc -match 'printf ''%s\\n'' ''\{"version":1,"hooks":\{\}\}''') 'laptop-exec-setup writes empty project hooks.json'

Assert (
    ($wrapSrc -match 'Fail-open wrapper') -and
    ($wrapSrc -match 'set \+e') -and
    ($wrapSrc -match 'WRAP_FAIL_OPEN') -and
    ($wrapSrc -match 'printf ''%s\\n'' "\$ALLOW"')
) 'guard-wrap fail-open (never lock agent on guard failure)'

Assert (
    ($hooksUserSrc -notmatch 'preToolUse[\s\S]{0,200}Shell') -and
    ($setupSrc -match 'HOOK_MATCHER="Grep\|Glob\|Read\|Write\|Edit\|EditNotebook\|StrReplace\|Delete\|Task"')
) 'preToolUse matcher excludes Shell (golden + setup)'

Assert (
    ($leSrc -match '\|-i\|--ignore-case') -and
    ($leSrc -match 'Never pass -i/-l/-n/--glob')
) 'laptop-exec rg rejects -i'

Assert (
    ($leSrc -match '--glob') -and
    ($leSrc -match 'Use pathspecs not --glob')
) 'laptop-exec rg rejects --glob'

Assert (
    ($leSrc -match 'for _i in 0 1 2 3 4 5 6 7') -and
    ($leSrc -match 'max 8 concurrent SSH channels')
) 'laptop-exec caps mux at 8 concurrent slots'

Assert (
    ($leSrc -match 'TUNNEL_PORT_MISSING') -and
    ($leSrc -match 'warn: TUNNEL_PORT_MISSING')
) 'laptop-exec loud TUNNEL_PORT_MISSING on blank conf'

Assert (
    (Test-Path -LiteralPath $sudo) -and
    ($installSrc -match 'install -m 755 "\$SERVER_DIR/sudo-from-laptop\.sh" /usr/local/bin/sudo-from-laptop')
) 'sudo-from-laptop exists and install.sh deploys it'

Assert (
    ($deploySrc -match 'skills/laptop-exec/SKILL\.md') -and
    ($deploySrc -match 'cursor-rules/laptop-exec\.mdc')
) 'deploy-laptop-exec installs skill+rule'

Assert (
    ($installSrc -match 'skills/laptop-exec/SKILL\.md') -and
    ($installSrc -match 'cursor-rules/laptop-exec\.mdc')
) 'install.sh deploys skill+rule to users'

Assert ($installSrc -match 'hooks-project\.json') 'install.sh deploys golden hooks-project.json'

Assert (
    ($leSrc -notmatch 'cmd /c exit 0') -and
    ($mountSrc -notmatch 'cmd /c exit 0') -and
    ($healSrc -notmatch 'cmd /c exit 0')
) 'laptop-exec/mount/heal have no cmd /c exit 0'

Assert (
    ($pushSrc -match 'WindowStyle Hidden') -and
    ($pushSrc -match 'EncodedCommand') -and
    ($pushSrc -match 'ssh_l_ps_hidden')
) 'push-laptop uses Hidden EncodedCommand probe'

Write-Host ''
Write-Host ("Passed: {0}  Failed: {1}" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
Write-Host 'HARD server laptop-exec batch: ALL PASS' -ForegroundColor Green
exit 0
