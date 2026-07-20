Set-Location 'D:\Smart\Claude-Code-Server'
$fail=@()
function Hit($n,$ok,$d=''){ if($ok){"PASS $n"} else {"FAIL $n :: $d"; $script:fail+=$n} }

$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
$ct=[IO.File]::ReadAllText('scripts\client\windows\connect.ps1')

Hit 'mac-seq12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
Hit 'mac-recover' (($gs -match 'sshx "timeout 30 \$CM recover-one') -and ($gs -notmatch 'timeout 30 sshx "\$CM recover-one'))
Hit 'win-banner-budget' ($ps -match 'banner_miss_tcp_open_budget')
Hit 'win-ensure-reseed' ($ps -match 'action=reseed')
Hit 'curly' ($ct -notmatch '[\u201C\u201D\u2018\u2019\u2014\u2013]')

# Win no_proc softfail hard drop
$noProc = Select-String -Path scripts\client\git-mode.ps1 -Pattern 'no_proc_tcp_open' -Context 0,12 | Out-String
Hit 'win-noproc-drop' ($ps -match 'no_proc_tcp_open_budget' -or ($noProc -match 'TunnelSoftFailCount -ge 6' -and $noProc -match 'return \$false')) $noProc.Substring(0,[Math]::Min(400,$noProc.Length))

# askpass echo password
Hit 'no-askpass-echo-pw' ($gs -notmatch 'echo \$LAPTOP_ADMIN_PW' -and $gs -notmatch 'echo "\$LAPTOP_ADMIN_PW"')

# connect-design persian
$cd=Get-ChildItem -Recurse -Filter 'connect-design.ps1' -EA SilentlyContinue | Select-Object -First 1
if($cd){
  $c=[IO.File]::ReadAllText($cd.FullName)
  Hit 'design-useVk' ($c -match 'useVk' -and $c -notmatch "KeyChar -eq 'q' -or.*ConsoleKey::Q")
} else { 'no connect-design.ps1' }

# SS:UNKNOWN
Hit 'ss-unknown' ($ps -match 'SS:UNKNOWN' -or $gs -match 'SS:UNKNOWN')

"FAILS=$($fail.Count) $($fail -join ',')"

# show no_proc region
Select-String -Path scripts\client\git-mode.ps1 -Pattern 'no_proc_tcp_open' -Context 0,15 | ForEach-Object {
  "L$($_.LineNumber):$($_.Line.Trim())"
  $_.Context.PostContext | ForEach-Object { "  $_" }
}
