$ErrorActionPreference='Continue'
$files=@(
  'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
)
foreach($f in $files){
  Write-Output "==== FILE $f ===="
  Select-String -Path $f -Pattern 'function\s+.*Tunnel|TUNNEL_UP|local_port_open|Test-Tunnel|Get-Tunnel|TunnelBanner|banner|TUNNEL_DOWN|SESSION_STATUS|VERDICT_CODE|connection dropped|orphan's -ErrorAction SilentlyContinue |
    Select-Object -First 60 |
    ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
}
# Extract function bodies roughly by line ranges for key functions
$gm='D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$gl=Get-Content $gm
Write-Output '==== git-mode function index ===='
for($i=0;$i -lt $gl.Count;$i++){
  if($gl[$i] -match '^\s*function\s+'){ Write-Output ("{0}:{1}" -f ($i+1), $gl[$i].Trim()) }
}
