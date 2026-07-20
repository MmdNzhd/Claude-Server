Set-Location 'D:\Smart\Claude-Code-Server'
$fail=@()
function Hit($n,$ok,$d){ if($ok){"PASS $n"}else{"FAIL $n :: $d"; $script:fail+=$n} }

$t=[IO.File]::ReadAllText('scripts\client\windows\connect.ps1')
Hit 'curly' ($t -notmatch '[\u201C\u201D\u2018\u2019]') 'curly'
$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
Hit 'seq12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4')) 'seq'
Hit 'recover' ($gs -notmatch 'timeout 30 sshx "\$CM recover-one') 'nested'
# indent recover line
$gl=Get-Content scripts\client\git-mode.sh
if($gl[1003] -match '^sshx ' -and $gl[1003] -notmatch '^    '){
  $gl[1003]='    '+$gl[1003].TrimStart()
  $gl | Set-Content scripts\client\git-mode.sh -Encoding utf8
  'fixed recover indent'
}
$gmp=Get-Content scripts\client\git-mode.ps1 -Raw
Hit 'banner-budget' ($gmp -match 'banner_miss_tcp_open_budget') 'no budget drop'
Hit 'ensure-reseed' ($gmp -match 'banner_miss_tcp_open action=reseed') 'ensure still reuses'

# credentials: only real assignment outside throw here-strings - check no = 'sepidz@Admin' in Get-Deploy
$cred=Get-Content publish\Get-DeployCredentials.ps1 -Raw
Hit 'no-sepidzAdmin-assign' ($cred -notmatch "SepidzSudoPassword\s*=\s*'sepidz@Admin'") 'hardcoded'

Write-Output "static_fails=$($fail.Count)"

$p=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1') -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\pipe3.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\pipe3.err'
[void]$p.WaitForExit(180000)
"pipeline_exit=$($p.ExitCode)"
Select-String -Path scripts\tmp\pipe3.txt -Pattern 'FAIL |test\(s\) failed|All .*passed|failed\.' | ForEach-Object { $_.Line }

$p2=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1') -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\gm3.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\gm3.err'
[void]$p2.WaitForExit(180000)
"gitmode_exit=$($p2.ExitCode)"
Select-String -Path scripts\tmp\gm3.txt -Pattern 'FAIL |passed|failed' | Select-Object -Last 8 | ForEach-Object { $_.Line }
