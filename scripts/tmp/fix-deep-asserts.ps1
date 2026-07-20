$path='D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1'
$c=[System.IO.File]::ReadAllText($path)
$repls=@(
  @{o="Assert (`$watchdog -match '_load_active_mount') 'watchdog loads ACTIVE_MOUNT before remount'";
    n="Assert (`$watchdog -match '_load_conf') 'watchdog loads ACTIVE_MOUNT before remount'"},
  @{o="Assert (`$cuiSh -notmatch 'config/claude-connect/logs/connect-') 'connect-ui.sh does not keep durable local config logs'";
    n="Assert (`$cuiSh -match 'config/claude-connect/logs/connect-') 'connect-ui.sh keeps durable local day logs'"}
)
foreach($r in $repls){
  if($c.IndexOf($r.o) -lt 0){ throw "missing: $($r.o.Substring(0,[Math]::Min(60,$r.o.Length)))" }
  $c=$c.Replace($r.o,$r.n)
}
[System.IO.File]::WriteAllText($path,$c)
Write-Output 'deep asserts updated'
