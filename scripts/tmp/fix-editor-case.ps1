Set-Location 'D:\Smart\Claude-Code-Server'
$utf8=New-Object System.Text.UTF8Encoding $false
$p=(Resolve-Path 'scripts\client\editor-launch.sh').Path
$t=[IO.File]::ReadAllText($p)
$old='            case "$cmd" in *folder-uri*) ;; *) return 0 ;; esac'
$new="            # URI-less profile main only.`n            if [[ `"`$cmd`" != *folder-uri* ]]; then return 0; fi"
if(-not $t.Contains($old)){ throw 'pattern not found' }
$t=$t.Replace($old,$new)
[IO.File]::WriteAllText($p,$t,$utf8)
$sh=[IO.File]::ReadAllText($p)
$pat='folder-uri\*\).*return 0'
"bad_match=$($sh -match $pat)"

$p2=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\g3.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\g3.err'
[void]$p2.WaitForExit(120000)
"gitmode_exit=$($p2.ExitCode)"
Select-String scripts\tmp\g3.txt -Pattern 'FAIL |All deep|failed' | Select-Object -Last 5 | ForEach-Object { $_.Line }

$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
$err=$null;[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\git-mode.ps1'),[ref]$null,[ref]$err)
"P0 seq12=$($gs -match 'seq 1 12' -and $gs -notmatch 'seq 1 4') nest=$($gs -match 'timeout 30 sshx \"\$CM recover-one') budget=$($ps -match 'banner_miss_tcp_open_budget') parse=$($err.Count)"
