$ErrorActionPreference = 'Continue'
Write-Host 'kill stale ssh'
Get-Process ssh -ErrorAction SilentlyContinue | ForEach-Object {
  try { $_.Kill() } catch {}
}
Start-Sleep -Seconds 1
function T($name,$args){
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $p=Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\ssh-$name.out" -RedirectStandardError "$env:TEMP\ssh-$name.err"
  if(-not $p.WaitForExit(15000)){ try{$p.Kill()}catch{}; Write-Host "$name TIMEOUT ms=$($sw.ElapsedMilliseconds)"; Get-Content "$env:TEMP\ssh-$name.err" -EA SilentlyContinue; return }
  $o=((Get-Content "$env:TEMP\ssh-$name.out" -Raw)+'').Trim()
  $e=((Get-Content "$env:TEMP\ssh-$name.err" -Raw)+'').Trim()
  Write-Host "$name ec=$($p.ExitCode) ms=$($sw.ElapsedMilliseconds) out=$o err=$e"
}
$opts=@('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','-o','StrictHostKeyChecking=accept-new')
T 'direct' ($opts + @('sepidz@192.168.250.70','cat /usr/local/share/claude-client/connect-version.txt'))
T 'alias' ($opts + @('claude-server-sepidz','cat /usr/local/share/claude-client/connect-version.txt'))
T 'withN' (@('-n') + $opts + @('sepidz@192.168.250.70','cat /usr/local/share/claude-client/connect-version.txt'))
T 'smart' ($opts + @('smart@192.168.210.240','cat /usr/local/share/claude-client/connect-version.txt'))
