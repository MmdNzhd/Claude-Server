$ErrorActionPreference='Continue'
function Dump($path,$from,$to) {
  Write-Output "===== $path $from-$to ====="
  $lines=Get-Content $path
  for ($i=$from; $i -le $to; $i++) { '{0,4}|{1}' -f $i, $lines[$i-1] }
}
Dump 'scripts/client/git-mode.ps1' 30 45
Dump 'scripts/client/git-mode.ps1' 160 195
Dump 'scripts/client/git-mode.ps1' 320 400
Dump 'scripts/client/git-mode.ps1' 700 780
# mac fetch_tunnel_banner + test_tunnel_up + sync
$sh='scripts/client/git-mode.sh'
Select-String -Path $sh -Pattern '^(fetch_tunnel_banner|get_tunnel_banner|test_tunnel_up|tunnel_up|sync_session|tunnel_banner_is)' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line }
Dump $sh 360 450
# find sync in sh
$idx = (Select-String -Path $sh -Pattern 'sync_session_tunnel|bg_alive_forward').LineNumber | Select-Object -First 3
foreach ($n in $idx) { Dump $sh ($n-5) ($n+40) }
Dump 'scripts/client/connect-diagnostic.ps1' 42 55
Dump 'scripts/client/connect-diagnostic.ps1' 210 270
Dump 'scripts/client/windows/connect.ps1' 1445 1500
# bat version guard
Select-String -Path 'scripts/client/windows/connect.bat','scripts/client/mac/connect.sh' -Pattern '20260717' |
  ForEach-Object { '{0}: {1}' -f ($_.Path|Split-Path -Leaf), $_.Line.Trim() }
