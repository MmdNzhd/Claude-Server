Set-Location 'D:\Smart\Claude-Code-Server'
$fail=@()
function Hit($n,$ok){ if($ok){"PASS $n"}else{"FAIL $n"; $script:fail+=$n} }
$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
$ct=[IO.File]::ReadAllText('scripts\client\windows\connect.ps1')
$err=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\git-mode.ps1'),[ref]$null,[ref]$err)
Hit 'parse-git-mode' ($err.Count -eq 0)
Hit 'seq12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
Hit 'recover' (($gs -match 'sshx "timeout 30 \$CM recover-one') -and ($gs -notmatch 'timeout 30 sshx "\$CM recover-one'))
Hit 'budget' ($ps -match 'banner_miss_tcp_open_budget')
Hit 'reseed' ($ps -match 'action=reseed')
Hit 'curly' ($ct -notmatch '[\u201C\u201D\u2018\u2019]')
"STATIC=$($fail.Count)"

$p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\g1.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\g1.err'
[void]$p.WaitForExit(120000)
"pipeline_exit=$($p.ExitCode)"; Select-String scripts\tmp\g1.txt -Pattern 'FAIL |All tests passed|failed\.' | %{$_.Line}

$p2=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\g2.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\g2.err'
[void]$p2.WaitForExit(120000)
"gitmode_exit=$($p2.ExitCode)"; Select-String scripts\tmp\g2.txt -Pattern 'FAIL |All deep|failed' | Select-Object -Last 4 | %{$_.Line}

Start-Sleep 2
$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
Hit 'post-seq' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
Hit 'post-recover' ($gs -notmatch 'timeout 30 sshx "\$CM recover-one')
Hit 'post-budget' ($ps -match 'banner_miss_tcp_open_budget')
Hit 'post-parse' ({ $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\git-mode.ps1'),[ref]$null,[ref]$e); $e.Count -eq 0 }.Invoke())
"FINAL_FAILS=$($fail.Count) $($fail -join ',')"
@"
# LOCK STATUS $(Get-Date -Format o)
STATIC_AND_TESTS: $(if($fail.Count -eq 0 -and $p.ExitCode -eq 0){'GREEN'}else{'RED'})
P0 mac seq/recover + win banner/ensure + parse OK required before deploy approval.
"@ | Set-Content scripts\tmp\LOCK-STATUS.md
