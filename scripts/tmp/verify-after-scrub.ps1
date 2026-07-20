Set-Location 'D:\Smart\Claude-Code-Server'
$fail=@()
function Hit($n,$ok,$d=''){ if($ok){"PASS $n"}else{"FAIL $n :: $d"; $script:fail+=$n} }

$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
$ct=[IO.File]::ReadAllText('scripts\client\windows\connect.ps1')
$ui=[IO.File]::ReadAllText('scripts\client\connect-ui.ps1')

Hit 'seq12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
Hit 'recover' (($gs -match 'sshx "timeout 30 \$CM recover-one') -and ($gs -notmatch 'timeout 30 sshx "\$CM recover-one'))
Hit 'budget' ($ps -match 'banner_miss_tcp_open_budget')
Hit 'noproc' ($ps -match 'no_proc_tcp_open_budget')
Hit 'reseed' ($ps -match 'action=reseed')
Hit 'ss' (($ps -match 'SS:UNKNOWN') -and ($gs -match 'SS:UNKNOWN'))
Hit 'curly-c' ($ct -notmatch '[\u201C\u201D\u2018\u2019\u2014\u2013]')
Hit 'curly-ui' ($ui -notmatch '[\u201C\u201D\u2018\u2019\u2014\u2013]')
Hit 'cr-strip' ((Get-Content scripts\server\claude-mount.sh -Raw) -match "tr -d '\\r'")

# sticky force?
$stickyForce = $false
$lines=Get-Content scripts\client\windows\connect.ps1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'EditorSeenOpen' -and $lines[$i] -match 'editorOpened\s*=\s*\$true' -and $lines[$i] -notmatch 'if \(\$editorOpened\)'){
    $stickyForce=$true; "sticky-force L$($i+1):$($lines[$i].Trim())"
  }
}
Hit 'no-sticky-force-editorOpened' (-not $stickyForce)

# show lines around 1728 1812
1725..1745 | ForEach-Object { if($_ -le $lines.Count){ '{0}|{1}' -f $_, $lines[$_-1] } }
'---'
1808..1820 | ForEach-Object { if($_ -le $lines.Count){ '{0}|{1}' -f $_, $lines[$_-1] } }

$err=$null;[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\git-mode.ps1'),[ref]$null,[ref]$err)
Hit 'parse' ($err.Count -eq 0)

$p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\v2-pipe.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\v2-pipe.err'
[void]$p.WaitForExit(180000)
"pipeline=$($p.ExitCode)"; Select-String scripts\tmp\v2-pipe.txt -Pattern 'FAIL |All tests passed|failed\.' | %{$_.Line}

$p2=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\v2-gm.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\v2-gm.err'
[void]$p2.WaitForExit(180000)
"gitmode=$($p2.ExitCode)"; Select-String scripts\tmp\v2-gm.txt -Pattern 'FAIL |All deep|failed' | Select-Object -Last 3 | %{$_.Line}

foreach($c in @('test-tunnel-contracts.ps1','test-log-sync-contracts.ps1','test-mount-contracts.ps1','test-security-contracts.ps1')){
  $path="scripts\tmp\$c"
  if(Test-Path $path){
    $r=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',(Resolve-Path $path) -NoNewWindow -PassThru -RedirectStandardOutput "scripts\tmp\$c.out2" -RedirectStandardError "scripts\tmp\$c.err2"
    [void]$r.WaitForExit(90000)
    "$c=$($r.ExitCode)"
    if($r.ExitCode -ne 0){ Select-String "scripts\tmp\$c.out2" -Pattern 'FAIL|fail' | Select-Object -First 5 | %{$_.Line} }
  }
}

"STATIC_FAILS=$($fail.Count) $($fail -join ',')"
