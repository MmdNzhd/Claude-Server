Set-Location 'D:\Smart\Claude-Code-Server'
$fail=@()
function Hit($n,$ok,$d=''){ if($ok){"PASS $n"}else{"FAIL $n :: $d"; $script:fail+=$n} }
$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
$ct=[IO.File]::ReadAllText('scripts\client\windows\connect.ps1')
$auth=[IO.File]::ReadAllText('scripts\client\cursor-auth-laptop.ps1')
Hit 'mac-seq-12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
Hit 'mac-recover' (($gs -match 'sshx "timeout 30 \$CM recover-one') -and ($gs -notmatch 'timeout 30 sshx "\$CM recover-one'))
Hit 'win-banner-budget' ($ps -match 'banner_miss_tcp_open_budget')
Hit 'win-ensure-reseed' ($ps -match 'action=reseed')
Hit 'curly' ($ct -notmatch '[\u201C\u201D\u2018\u2019]')
Hit 'auth-temp' ($auth -match 'Remove-CursorAuthTempDir' -and $auth -match 'Get-CursorAuthTempRoot')
# pushconf || true on RESULT path
$push=(Select-String -Path scripts\client\git-mode.sh -Pattern 'push_server_connect_conf|PUSH_CONF' -Context 0,0 | Select-Object -First 5)
Hit 'pushconf-fn' ($gs -match 'PUSH_CONF_RESULT')
# reports
Write-Output '=== reports ==='
Get-ChildItem scripts\tmp\SWEEP*.md,scripts\tmp\FINAL*.md,scripts\tmp\FIX-W*.md,scripts\tmp\ATOMIC*.md,scripts\tmp\VERIFY*.md -EA SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 15 | ForEach-Object { "$($_.LastWriteTime.ToString('HH:mm:ss')) $($_.Name) $($_.Length)" }
"GATE_FAILS=$($fail.Count) $($fail -join ',')"
Get-Item scripts\client\git-mode.sh,scripts\client\git-mode.ps1,scripts\client\windows\connect.ps1 | Format-Table Name,Length,LastWriteTime -AutoSize
