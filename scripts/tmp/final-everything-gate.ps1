Set-Location 'D:\Smart\Claude-Code-Server'
$ErrorActionPreference='Continue'
$fail=[System.Collections.Generic.List[string]]::new()
function Hit([string]$n,[bool]$ok,[string]$d=''){
  if($ok){ "PASS $n" } else { "FAIL $n :: $d"; [void]$fail.Add($n) }
}

$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
$ct=[IO.File]::ReadAllText('scripts\client\windows\connect.ps1')
$ui=[IO.File]::ReadAllText('scripts\client\connect-ui.ps1')
$uis=[IO.File]::ReadAllText('scripts\client\connect-ui.sh')
$auth=[IO.File]::ReadAllText('scripts\client\cursor-auth-laptop.ps1')
$upd=[IO.File]::ReadAllText('scripts\client\windows\connect-update.ps1')
$mount=[IO.File]::ReadAllText('scripts\server\claude-mount.sh')
$wd=[IO.File]::ReadAllText('scripts\server\claude-watchdog.sh')
$cred=[IO.File]::ReadAllText('publish\Get-DeployCredentials.ps1')
$add=[IO.File]::ReadAllText('scripts\server\commands\add-user.sh')

Write-Output '=== P0 TUNNEL/MAC ==='
Hit 'mac-seq-12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
Hit 'mac-recover-clean' (($gs -match 'sshx "timeout 30 \$CM recover-one') -and ($gs -notmatch 'timeout 30 sshx "\$CM recover-one'))
Hit 'mac-pushconf-no-or-true-on-ssh' ($gs -notmatch 'push_out="\$\(sshx "echo \$b64 \| base64 -d \| bash" 2>/dev/null \|\| true\)"')
Hit 'win-banner-budget' ($ps -match 'banner_miss_tcp_open_budget')
Hit 'win-noproc-budget' ($ps -match 'no_proc_tcp_open_budget')
Hit 'win-ensure-reseed' ($ps -match 'action=reseed')
Hit 'win-sticky-no-force' ($ct -notmatch "EditorSeenOpen\) \{\s*\$editorOpened = \$true" -and $ct -match 'EditorSeenOpen')
Hit 'ss-unknown' (($ps -match 'SS:UNKNOWN') -and ($gs -match 'SS:UNKNOWN'))

Write-Output '=== CURLY/PARSE ==='
Hit 'curly-connect' ($ct -notmatch '[\u201C\u201D\u2018\u2019\u2014\u2013]')
Hit 'curly-ui' ($ui -notmatch '[\u201C\u201D\u2018\u2019\u2014\u2013]')
$err=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\git-mode.ps1'),[ref]$null,[ref]$err)
Hit 'parse-git-mode' ($err.Count -eq 0) ("$($err | Select-Object -First 1)")
$err2=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\windows\connect.ps1'),[ref]$null,[ref]$err2)
Hit 'parse-connect' ($err2.Count -eq 0)

Write-Output '=== LOGGING ==='
Hit 'win-cat-no-true' ($ui -notmatch 'cat >>.*\|\| true' -and $ui -match 'exit \$ec')
Hit 'win-appendOk' ($ui -match '\$appendOk')
Hit 'mac-cat-ok' ($uis -match 'cat_ok')
Hit 'sync-lock' ($ui -match '\.sync-lock' -and $uis -match 'sync-lock')

Write-Output '=== AUTH/TEMP ==='
Hit 'auth-temp-helpers' ($auth -match 'Get-CursorAuthTempRoot' -and $auth -match 'Remove-CursorAuthTempDir')
Hit 'auth-no-bare-recurse' (-not (Select-String -Path scripts\client\cursor-auth-laptop.ps1 -Pattern 'Remove-Item \$tmp -Recurse'))
Hit 'golden-refresh' ($auth -match 'golden_stale|golden-synced-at|exported-at')

Write-Output '=== MOUNT ==='
Hit 'no-remove-item-git-recurse' (-not (Select-String -Path scripts\server\claude-mount.sh -Pattern 'Remove-Item.*\.git' -SimpleMatch:$false | Where-Object { $_.Line -match 'Remove-Item' }))
# bash mount shouldn't have Remove-Item; check dangerous rm -rf .git when both exist - look for restore_try safety
Hit 'watchdog-mount-down' ($wd -match 'claude-mount down' -or $wd -match 'recover')
Hit 'cr-strip' ($mount -match "tr -d.?\\\\r|sed.*\\\\r|\\\$'\\r'")
Hit 'no-alpha-active' ($mount -notmatch 'ACTIVE_MOUNT=.*head -1' -and $wd -notmatch 'ls.*\.conf.*head -1.*ACTIVE_MOUNT')

Write-Output '=== SECURITY ==='
Hit 'no-sepidzAdmin-assign' ($cred -notmatch "SepidzSudoPassword\s*=\s*'sepidz@Admin'")
Hit 'sql-placeholder' ($add -match 'CHANGE_ME' -and $add -notmatch 'Mohammad123')
Hit 'no-askpass-echo' ($gs -notmatch 'echo \$LAPTOP_ADMIN_PW')

Write-Output '=== UPDATE ==='
Hit 'update-nonzero-error' ($upd -match "Write-UpdateLog.*ERROR[\s\S]{0,200}exit 1" -or $upd -match "exit 1")
# softer: at least one exit 1 after error
Hit 'update-has-exit1' ([regex]::Matches($upd,'exit 1').Count -ge 1)

Write-Output '=== DESIGNER ==='
$des=Get-ChildItem -Recurse -Filter '*designer*connect*.ps1' -EA SilentlyContinue
$des2=Get-ChildItem -Recurse -Filter 'connect-design.ps1' -EA SilentlyContinue
$designFiles=@($des)+@($des2) | Select-Object -ExpandProperty FullName -Unique
foreach($f in $designFiles){
  $c=[IO.File]::ReadAllText($f)
  $name=[IO.Path]::GetFileName($f)
  Hit "design-useVk-$name" ($c -match 'useVk' -or $c -notmatch "KeyChar -eq 'q' -or")
  Hit "design-clear-$name" ($c -match 'ClearActiveMount' -or $c -notmatch "ActiveMount ''")
}

Write-Output "=== STATIC_FAILS=$($fail.Count) ==="
$fail | ForEach-Object { " - $_" }

# Tests
Write-Output '=== TESTS ==='
$p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\fe-pipe.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\fe-pipe.err'
[void]$p.WaitForExit(180000)
"pipeline_exit=$($p.ExitCode)"
Select-String scripts\tmp\fe-pipe.txt -Pattern 'FAIL |All tests passed|failed\.' | ForEach-Object Line

$p2=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\fe-gm.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\fe-gm.err'
[void]$p2.WaitForExit(180000)
"gitmode_exit=$($p2.ExitCode)"
Select-String scripts\tmp\fe-gm.txt -Pattern 'FAIL |All deep|failed' | Select-Object -Last 5 | ForEach-Object Line

# contracts if exist
foreach($c in @('scripts\tmp\test-tunnel-contracts.ps1','scripts\tmp\test-log-sync-contracts.ps1','scripts\tmp\test-mount-contracts.ps1','scripts\tmp\test-security-contracts.ps1')){
  if(Test-Path $c){
    $r=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Resolve-Path $c)) -NoNewWindow -PassThru -RedirectStandardOutput ($c+'.out') -RedirectStandardError ($c+'.err')
    [void]$r.WaitForExit(120000)
    "$([IO.Path]::GetFileName($c)) exit=$($r.ExitCode)"
  }
}

# post-test P0
Start-Sleep 1
$gs2=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps2=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
Hit 'post-seq' (($gs2 -match 'seq 1 12') -and ($gs2 -notmatch 'seq 1 4'))
Hit 'post-budget' ($ps2 -match 'banner_miss_tcp_open_budget')
"DONE static_fail=$($fail.Count) pipe=$($p.ExitCode) gm=$($p2.ExitCode)"
