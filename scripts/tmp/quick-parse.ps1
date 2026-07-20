Set-Location 'D:\Smart\Claude-Code-Server'
$err=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\git-mode.ps1'),[ref]$null,[ref]$err)
"parse=$($err.Count)"
if($err){$err|Select-Object -First 5|%{$_.ToString()}}
$lines=Get-Content scripts\client\git-mode.ps1
500..545|%{ '{0}|{1}' -f $_, $lines[$_-1] }
'---'
865..895|%{ '{0}|{1}' -f $_, $lines[$_-1] }
$gs=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
$ps=[IO.File]::ReadAllText('scripts\client\git-mode.ps1')
"seq12=$($gs -match 'seq 1 12' -and $gs -notmatch 'seq 1 4') recover_ok=$($gs -notmatch 'timeout 30 sshx \"\$CM recover-one') budget=$($ps -match 'banner_miss_tcp_open_budget') reseed=$($ps -match 'action=reseed')"
