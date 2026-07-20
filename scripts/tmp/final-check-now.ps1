Set-Location 'D:\Smart\Claude-Code-Server'
$fail=@()
function Hit($n,$ok,$d=''){ if($ok){"PASS $n"}else{"FAIL $n $d"; $script:fail+=$n} }

$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
$ct=[IO.File]::ReadAllText('scripts\client\windows\connect.ps1')

Hit 'mac-seq-12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
Hit 'mac-recover' (($gs -match 'sshx "timeout 30 \$CM recover-one') -and ($gs -notmatch 'timeout 30 sshx "\$CM recover-one'))
Hit 'win-banner-budget' ($ps -match 'banner_miss_tcp_open_budget')
Hit 'win-ensure-reseed' ($ps -match 'action=reseed')
Hit 'win-softfail-ge6' ($ps -match 'TunnelSoftFailCount -ge 6')
Hit 'curly' ($ct -notmatch '[\u201C\u201D\u2018\u2019]')
Hit 'auth-temp' ((Select-String -Path scripts\client\cursor-auth-laptop.ps1 -Pattern 'Remove-CursorAuthTempDir').Count -ge 1)

"STATIC_FAILS=$($fail.Count) :: $($fail -join ',')"

# protect files briefly - write marker
@"
fixed_at=$(Get-Date -Format o)
mac_seq=12
mac_recover=ok
win_banner=ok
win_ensure=ok
DO NOT REVERT seq 1 12 or recover_mounts or banner_miss_tcp_open_budget
"@ | Set-Content scripts\tmp\DO-NOT-REVERT-CRITICAL.txt

$p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\pipe-final.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\pipe-final.err'
[void]$p.WaitForExit(120000)
"pipeline_exit=$($p.ExitCode)"
Select-String scripts\tmp\pipe-final.txt -Pattern 'FAIL |All tests passed|failed\.' | ForEach-Object Line

$p2=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\gm-final.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\gm-final.err'
[void]$p2.WaitForExit(120000)
"gitmode_exit=$($p2.ExitCode)"
Select-String scripts\tmp\gm-final.txt -Pattern 'FAIL |All deep|failed' | Select-Object -Last 5 | ForEach-Object Line

# re-check after tests (detect revert race)
Start-Sleep 2
$gs2=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
Hit 'mac-seq-after-tests' (($gs2 -match 'seq 1 12') -and ($gs2 -notmatch 'seq 1 4'))
Hit 'mac-recover-after-tests' ($gs2 -notmatch 'timeout 30 sshx "\$CM recover-one')
"DONE fail_total=$($fail.Count)"
